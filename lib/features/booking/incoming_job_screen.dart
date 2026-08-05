import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../repositories/job_credits_repository.dart';
import '../../services/socket_service.dart';
import '../../services/location_service.dart';
import '../../services/alert_sound_service.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_pressable.dart';

/// Shown as a full-screen modal when the worker receives job requests.
/// Handles a QUEUE of multiple simultaneous requests from different customers.
/// Worker can Accept one (auto-declines others) or Decline individual ones.
class IncomingJobScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> bookingData;

  const IncomingJobScreen({super.key, required this.bookingData});

  @override
  ConsumerState<IncomingJobScreen> createState() => _IncomingJobScreenState();
}

class _IncomingJobScreenState extends ConsumerState<IncomingJobScreen>
    with WidgetsBindingObserver {
  // ── All pending requests for this worker ──────────────────────────────────
  late List<Map<String, dynamic>> _requests;
  int _currentIndex = 0;
  /// Booking ids this worker declined/dismissed during this screen session.
  final List<String> _declinedIds = [];

  // ── Per-request state ─────────────────────────────────────────────────────
  int _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds;

  /// Wall-clock deadline for the current request. The countdown derives from
  /// this on every tick instead of decrementing a counter — Android suspends
  /// Dart timers while the phone is locked, so a decrementing counter freezes
  /// and resumes stale, showing time that actually expired long ago.
  DateTime? _deadline;
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  bool _isProcessing = false;

  /// Resolved once in initState. Reading the provider from dispose() can throw
  /// while the tree tears down, which used to swallow the stop and leave the
  /// ring looping forever.
  AlertSoundService? _alertSound;
  bool _alertStopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requests = [widget.bookingData];
    unawaited(_loadMyPosition());
    unawaited(_loadCreditBalance());
    _startTimer();
    _socketSub =
        ref.read(socketServiceProvider).notifications.listen(_onSocketEvent);
    // Swiggy-style loop while this accept card is on screen.
    _alertSound = ref.read(alertSoundServiceProvider);
    unawaited(_alertSound!.startIncomingJobAlert());
    // Enrich FCM-minimal payloads immediately (language, description, etc.)
    // and again shortly after in case the pending list was still settling.
    unawaited(_refreshPendingRequests());
    Future.delayed(
      const Duration(seconds: 2),
      () => unawaited(_refreshPendingRequests()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _socketSub?.cancel();
    _stopAlert();
    super.dispose();
  }

  /// Idempotent — accept/decline stop the ring before popping, dispose is the
  /// backstop for every other exit (system back, tree teardown, queue empty).
  void _stopAlert() {
    if (_alertStopped) return;
    _alertStopped = true;
    unawaited(_alertSound?.stopIncomingJobAlert() ?? Future<void>.value());
  }

  /// The queue moved on to another request while the card stayed open.
  void _resumeAlert() {
    if (!_alertStopped || !mounted) return;
    _alertStopped = false;
    unawaited(_alertSound?.startIncomingJobAlert() ?? Future<void>.value());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Phone unlocked: re-sync the countdown from the wall clock right now.
      // Requests that expired while locked are auto-declined instead of
      // showing a frozen timer that errors on Accept.
      _tick();
      unawaited(_refreshPendingRequests());
    }
  }

  // ── Distance to the job ("· 2.3 km away") ───────────────────────────

  /// Worker's own GPS, fetched once when the card opens. Computed client-side
  /// (vs server-side) so it's accurate to where the worker is NOW, whether
  /// the offer arrived via socket, FCM tap, or the pending poll.
  ({double lat, double lng})? _myPos;

  Future<void> _loadMyPosition() async {
    try {
      final pos =
          await ref.read(locationServiceProvider).getCurrentPosition();
      if (pos != null && mounted) {
        setState(() => _myPos = (lat: pos.latitude, lng: pos.longitude));
      }
    } catch (_) {}
  }

  /// Haversine distance (km) from the worker to this request's job site.
  /// Null when either side's coords are unavailable — the card then shows
  /// the address alone.
  double? _distanceKmFor(Map<String, dynamic> r) {
    final me = _myPos;
    final lat = double.tryParse('${r['serviceLat'] ?? ''}');
    final lng = double.tryParse('${r['serviceLng'] ?? ''}');
    if (me == null || lat == null || lng == null) return null;
    const rEarth = 6371.0;
    final dLat = (lat - me.lat) * math.pi / 180;
    final dLng = (lng - me.lng) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(me.lat * math.pi / 180) *
            math.cos(lat * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return rEarth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // ── Job-credit cost ("N credits · remaining") ───────────────────

  /// Worker's current job-credit balance, fetched once when the card opens
  /// so the pro sees the COST of accepting before deciding. Null = still
  /// loading / fetch failed → the credits row is simply omitted.
  int? _creditBalance;

  /// From Master Entries `job_credit_per_accept` (default 15).
  int _creditsPerAccept = 15;

  List<String> _languageList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    final text = raw.toString().trim();
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _loadCreditBalance() async {
    try {
      final info =
          await ref.read(jobCreditsRepositoryProvider).getBalanceInfo();
      if (mounted) {
        setState(() {
          _creditBalance = info.balance;
          _creditsPerAccept = info.creditsPerAccept;
        });
      }
    } catch (_) {}
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();

    // Prefer notifiedAt (fresh wave-2 offer clock) over createdAt so widened
    // rebroadcasts get a full accept window instead of an already-expired
    // createdAt + 90s deadline.
    var deadline = DateTime.now()
        .add(Duration(seconds: AppConfig.jobAcceptTimeoutSeconds));
    if (_requests.isNotEmpty && _currentIndex < _requests.length) {
      final currentRequest = _requests[_currentIndex];
      final notifiedAt = DateTime.tryParse(
              '${currentRequest['notifiedAt'] ?? ''}')
          ?.toLocal();
      final createdAt =
          DateTime.tryParse('${currentRequest['createdAt'] ?? ''}')?.toLocal();
      final anchor = notifiedAt ?? createdAt;
      if (anchor != null) {
        deadline =
            anchor.add(Duration(seconds: AppConfig.jobAcceptTimeoutSeconds));
      }
    }
    _deadline = deadline;

    _tick();
    if (_timer == null || !_timer!.isActive) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  /// Recompute remaining time from the wall clock. Runs every second while
  /// foregrounded AND immediately on resume after the phone unlocks.
  void _tick() {
    if (!mounted || _deadline == null) return;
    final remaining = _deadline!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _timer?.cancel();
      if (_isProcessing) return; // don't yank the card mid accept/decline
      setState(() => _secondsRemaining = 0);
      _autoDeclineCurrent();
      return;
    }
    if (remaining != _secondsRemaining) {
      setState(() => _secondsRemaining = remaining);
    }
  }

  void _resetTimerForNewRequest() {
    _startTimer();
  }

  // ── Socket-first queue updates + one-shot reconciliation ──────────────────

  void _onSocketEvent(Map<String, dynamic> event) {
    if (!mounted || event['_event'] != 'new_booking_request') return;
    final id = (event['id'] ?? event['bookingId'])?.toString();
    if (id == null ||
        _declinedIds.contains(id) ||
        _requests.any((r) => r['id']?.toString() == id)) {
      return;
    }
    setState(() => _requests.add(Map<String, dynamic>.from(event)));
  }

  Future<void> _refreshPendingRequests() async {
    if (!mounted) return;
    try {
      final all = await ref.read(bookingRepositoryProvider).getPendingBookings();
      if (!mounted) return;
      setState(() {
        final allMaps = all
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
        final validIds = allMaps.map((r) => r['id']?.toString()).toSet();
        // Remove requests that are no longer pending on the backend
        _requests.removeWhere((r) => !validIds.contains(r['id']?.toString()));
        if (_requests.isEmpty) {
          Navigator.pop(context, {
            'accepted': false,
            'declinedIds': List<String>.from(_declinedIds),
          });
          return;
        }
        if (_currentIndex >= _requests.length) {
          _currentIndex = 0;
          _resetTimerForNewRequest();
        }
        final existingIds = _requests.map((r) => r['id']?.toString()).toSet();
        for (final r in allMaps) {
          if (!existingIds.contains(r['id']?.toString())) {
            _requests.add(r);
          }
        }
        // ENRICH entries already on screen with the fresh server payload —
        // an offer opened from FCM starts with a minimal map (no coords →
        // no "km away" line); the poll returns full booking entities, so
        // merge them in (fresh values win, keep any extra local keys).
        final freshById = {
          for (final r in allMaps) r['id']?.toString(): r,
        };
        for (var i = 0; i < _requests.length; i++) {
          final fresh = freshById[_requests[i]['id']?.toString()];
          if (fresh != null) {
            _requests[i] = {..._requests[i], ...fresh};
          }
        }
      });
    } catch (e) {
      debugPrint('[IncomingJob] Queue reconciliation failed: $e');
    }
  }

  // ── Accept ────────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_isProcessing || _requests.isEmpty) return;
    setState(() => _isProcessing = true);
    _timer?.cancel();
    // Silence the ring on the tap, not after the network round-trip below —
    // accept + GPS seed can take seconds and the loop was still audible.
    _stopAlert();

    final current = _requests[_currentIndex];
    final bookingId = current['id'] as String?;

    try {
      if (bookingId == null) throw Exception('Missing booking ID');
      await ref.read(bookingRepositoryProvider).acceptBooking(bookingId);

      if (!mounted) return;

      // Start streaming worker's location to the customer
      final user = await ref.read(currentUserProvider.future);
      if (!mounted) return;
      if (user != null) {
        ref.read(socketServiceProvider).startLocationStream(user.id, bookingId);
        // Seed Redis immediately so customer status-poll can show a pin
        // before the first GPS stream tick arrives.
        try {
          final pos =
              await ref.read(locationServiceProvider).getCurrentPosition();
          if (pos != null && mounted) {
            await ref.read(workerRepositoryProvider).updateMyLocation(
                  lat: pos.latitude,
                  lng: pos.longitude,
                );
          }
        } catch (_) {}
      }
      if (!mounted) return;

      ref.invalidate(myBookingsProvider);

      // Show the snack BEFORE popping — after Navigator.pop the widget is
      // leaving the tree and its context is stale. Calling showGxSnack /
      // ScaffoldMessenger on a dead context throws silently and leaves a
      // black frame. The snack renders on the ScaffoldMessenger (root) and
      // persists naturally onto whatever screen comes next.
      showGxSnack(
        context,
        'Job Accepted! Head to the customer location.',
        type: GxSnackType.success,
        duration: const Duration(seconds: 4),
      );

      // Backend auto-cancels all other pending bookings for this worker.
      Navigator.pop(context, {'accepted': true, 'bookingId': bookingId});
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      // Extract the real server message (DioException.toString() hides it).
      String msg = e.toString();
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map && data['message'] != null) {
          msg = data['message'].toString();
        }
      }
      final lower = msg.toLowerCase();
      // Broadcast race lost (v126 first-accept-wins), or the request expired /
      // was cancelled while the phone was locked — drop the card gracefully
      // instead of showing a raw error.
      if (lower.contains('no longer available') ||
          lower.contains('already taken') ||
          lower.contains('not pending') ||
          lower.contains('expired') ||
          lower.contains('cancelled') ||
          lower.contains('not found') ||
          lower.contains('not assigned') ||
          lower.contains('was accepted')) {
        showGxSnack(context, 'Too late — this request is no longer available.',
            type: GxSnackType.info);
        setState(() {
          _requests.removeAt(_currentIndex);
          if (_currentIndex >= _requests.length) _currentIndex = 0;
        });
        if (_requests.isEmpty) {
          Navigator.pop(context, {
            'accepted': false,
            'declinedIds': List<String>.from(_declinedIds),
          });
          return;
        }
        _startTimer();
        return;
      }

      if (lower.contains('job credits left') || lower.contains('buy a pack')) {
        showGxSnack(context, msg, type: GxSnackType.error);
        // Signal the caller (main_wrapper / go_live_screen) to open the
        // pack screen AFTER we pop — we must NOT push on this context after
        // popping, that leaves a blank route on the stack (black screen bug).
        Navigator.pop(context, {
          'accepted': false,
          'openJobPack': true,
          'declinedIds': List<String>.from(_declinedIds),
        });
        return;
      }

      showGxSnack(context, 'Failed to accept: $msg', type: GxSnackType.error);
      _startTimer();
    }
  }

  // ── Decline current request ───────────────────────────────────────────────

  Future<void> _declineCurrent() async {
    _timer?.cancel();
    setState(() => _isProcessing = true);
    _stopAlert();

    final bookingId = _requests[_currentIndex]['id'] as String?;
    try {
      if (bookingId != null) {
        await ref.read(bookingRepositoryProvider).rejectBooking(bookingId);
        _declinedIds.add(bookingId);
      }
    } catch (e) {
      debugPrint('[IncomingJob] Decline failed: $e');
      // Still treat as declined locally so poll/FCM cannot reopen a card the
      // worker already dismissed (backend may have already removed pending).
      if (bookingId != null) _declinedIds.add(bookingId);
    }

    _removeCurrentAndAdvance();
  }

  Future<void> _autoDeclineCurrent() async {
    if (_requests.isEmpty || _currentIndex >= _requests.length) return;
    _stopAlert();
    final current = _requests[_currentIndex];
    final bookingId = current['id'] as String?;
    final attempt = int.tryParse('${current['attempt'] ?? '1'}') ?? 1;

    // Wave 1 soft-expire: do NOT call rejectBooking — that marks the worker
    // rejected for this customer+skill and blocks widened wave-2 offers.
    // Wave 2 (final) hard-rejects so Redis pending is cleared.
    try {
      if (bookingId != null && attempt >= 2) {
        await ref.read(bookingRepositoryProvider).rejectBooking(bookingId);
        _declinedIds.add(bookingId);
      } else if (bookingId != null) {
        _declinedIds.add(bookingId);
      }
    } catch (e) {
      debugPrint('[IncomingJob] Auto-decline failed: $e');
      if (bookingId != null) _declinedIds.add(bookingId);
    }
    _removeCurrentAndAdvance(isTimeout: true);
  }

  /// X button: permanently decline every queued request for this worker so
  /// poll/FCM/socket cannot reopen the same Instant Help cards.
  Future<void> _dismissAll() async {
    if (_isProcessing) return;
    _timer?.cancel();
    setState(() => _isProcessing = true);
    _stopAlert();
    final ids = _requests
        .map((r) => r['id'] as String?)
        .whereType<String>()
        .toList();
    for (final id in ids) {
      try {
        await ref.read(bookingRepositoryProvider).rejectBooking(id);
      } catch (e) {
        debugPrint('[IncomingJob] Dismiss decline failed for $id: $e');
      }
      _declinedIds.add(id);
    }
    if (!mounted) return;
    Navigator.pop(context, {
      'accepted': false,
      'declinedIds': List<String>.from(_declinedIds),
    });
  }

  void _removeCurrentAndAdvance({bool isTimeout = false}) {
    if (!mounted) return;
    // Capture the name of the request being removed BEFORE removeAt — after the
    // removal `_requests[_currentIndex]` points at the *next* request, so reading
    // it for the timeout message would name the wrong customer.
    final timedOutName = (_currentIndex >= 0 && _currentIndex < _requests.length)
        ? (_requests[_currentIndex]['customer_name'] as String? ?? 'customer')
        : 'customer';
    setState(() {
      _requests.removeAt(_currentIndex);
      _isProcessing = false;

      if (_requests.isEmpty) {
        // No more requests — close the screen
        Navigator.pop(context, {
          'accepted': false,
          'declinedIds': List<String>.from(_declinedIds),
        });
        return;
      }

      // Clamp index if we were at the last item
      if (_currentIndex >= _requests.length) {
        _currentIndex = _requests.length - 1;
      }

      // Start fresh timer for the next request
      _resetTimerForNewRequest();
      // Decline/timeout silenced the ring; the next queued request deserves
      // its own alert.
      _resumeAlert();

      if (isTimeout) {
        showGxSnack(
          context,
          'Request from $timedOutName timed out. Moving to next.',
          duration: const Duration(seconds: 2),
        );
      }
    });
  }

  // ── Navigate between queued requests ─────────────────────────────────────

  void _goToRequest(int index) {
    setState(() {
      _currentIndex = index;
      _resetTimerForNewRequest();
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_requests.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final err = Theme.of(context).colorScheme.error;
    final current = _requests[_currentIndex];
    final customer = current['customer'];
    final customerName = (current['customer_name'] as String?) ??
                         (customer is Map ? customer['name'] as String? : null) ??
                         'New Customer';
    final skill = current['skill'] as String? ?? 'General Help';
    final location = current['serviceLocation'] as String? ?? 'Nearby';
    final distanceKm = _distanceKmFor(current);
    final locationLine = distanceKm != null
        ? '$location · ${distanceKm.toStringAsFixed(1)} km away'
        : location;
    final amountRaw = current['amount'];
    final amount = amountRaw is num 
        ? amountRaw.toDouble() 
        : double.tryParse(amountRaw?.toString() ?? '0') ?? 0.0;
    // INSTANT broadcast jobs bill hourly: `amount` is the customer's ₹/hr
    // offer (billing = rate × worked time), not a flat total.
    final isHourlyRate =
        (current['type'] ?? 'INSTANT').toString().toUpperCase() == 'INSTANT';
    final totalRequests = _requests.length;
    final timerFraction =
        _secondsRemaining / AppConfig.jobAcceptTimeoutSeconds;

    return Scaffold(
      backgroundColor: gx.bg,
      // Pin Decline/Accept above the system nav bar. The middle scrolls so
      // short phones (credit + issue + language cards) never bury the CTAs.
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  // Close
                  IconButton(
                    tooltip: 'Dismiss request',
                    icon: Icon(Icons.close, color: gx.ink),
                    onPressed: _isProcessing ? null : _dismissAll,
                  ),
                  const Spacer(),
                  // Queue indicator badge
                  if (totalRequests > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentGold,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people, color: gx.onAccent, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$totalRequests requests waiting',
                            style: TextStyle(
                              color: gx.onAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: GixbeeTheme.accentGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on,
                              color: GixbeeTheme.accentGold, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'INSTANT REQUEST',
                            style: TextStyle(
                                color: GixbeeTheme.accentGold,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ── Queue tabs (visible when multiple requests) ─────────────────
            if (totalRequests > 1) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(totalRequests, (i) {
                    final isActive = i == _currentIndex;
                    final req = _requests[i];
                    return GestureDetector(
                      onTap: () => _goToRequest(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? gx.accent : gx.card2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive ? gx.accent : gx.border,
                          ),
                        ),
                        child: Text(
                          req['customer_name'] as String? ?? 'Request ${i + 1}',
                          style: TextStyle(
                            color: isActive ? gx.onAccent : gx.ink,
                            fontWeight: isActive
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
                child: Column(
                  children: [
                    // ── Countdown ring ──────────────────────────────────────
                    // Single coherent a11y label for the countdown — without
                    // this a screen reader reads the ring's two visual Text
                    // nodes as the disjoint "36" then "seconds", plus the
                    // progress indicator's raw percentage. ExcludeSemantics
                    // suppresses those noisy inner nodes.
                    Semantics(
                      label:
                          '$_secondsRemaining seconds remaining to respond to this request',
                      child: ExcludeSemantics(
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 110,
                              height: 110,
                              child: CircularProgressIndicator(
                                value: timerFraction,
                                strokeWidth: 8,
                                backgroundColor: gx.card2,
                                color: _secondsRemaining > 20
                                    ? GixbeeTheme.accentGreen
                                    : _secondsRemaining > 10
                                        ? GixbeeTheme.accentGold
                                        : err,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_secondsRemaining',
                                  style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: gx.ink),
                                ),
                                Text(
                                  'seconds',
                                  style:
                                      TextStyle(fontSize: 11, color: muted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Customer info ───────────────────────────────────────
                    Text(
                      customerName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: gx.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'needs a $skill',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, color: gx.accentSoft),
                    ),

                    const SizedBox(height: 24),

                    // ── Details cards ───────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          _DetailCard(
                            icon: Icons.location_on_rounded,
                            label: 'Location',
                            value: locationLine,
                            color: GixbeeTheme.accentBlue,
                          ),
                          const SizedBox(height: 12),
                          _DetailCard(
                            icon: Icons.payments_rounded,
                            label: isHourlyRate
                                ? "Customer's Rate"
                                : 'Job Amount',
                            value: isHourlyRate
                                ? '₹${amount.toStringAsFixed(0)}/hr · 1 hr minimum'
                                : '₹${amount.toStringAsFixed(0)}',
                            color: GixbeeTheme.accentGreen,
                          ),
                          // Cost transparency: accepting consumes a job credit —
                          // say so BEFORE the pro commits, with remaining balance.
                          if (_creditBalance != null) ...[
                            const SizedBox(height: 12),
                            _DetailCard(
                              icon: Icons.confirmation_num_outlined,
                              label: 'Job credit',
                              value: () {
                                final bal = _creditBalance!;
                                final cost = _creditsPerAccept;
                                if (cost <= 0) {
                                  return 'Accept is free (no credit charge)';
                                }
                                if (bal < cost) {
                                  return 'Need $cost credit${cost == 1 ? '' : 's'} — buy a pack to accept';
                                }
                                final remain = bal - cost;
                                return '$cost credit${cost == 1 ? '' : 's'} used on accept · $remain will remain';
                              }(),
                              color: _creditsPerAccept <= 0
                                  ? GixbeeTheme.accentTeal
                                  : _creditBalance! < _creditsPerAccept
                                      ? err
                                      : _creditBalance! == _creditsPerAccept
                                          ? GixbeeTheme.accentGold
                                          : GixbeeTheme.accentTeal,
                            ),
                          ],
                          // Uber-style broadcast requests carry the customer's
                          // issue description — show it so the pro can decide.
                          if ((current['description'] as String?)?.isNotEmpty ??
                              false) ...[
                            const SizedBox(height: 12),
                            _DetailCard(
                              icon: Icons.description_outlined,
                              label: 'Issue',
                              value: current['description'] as String,
                              color: gx.accentSoft,
                            ),
                          ],
                          // v126 language step: the customer's required languages.
                          if (_languageList(current['preferredLanguages'])
                              .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _DetailCard(
                              icon: Icons.translate_rounded,
                              label: 'Customer speaks',
                              value: _languageList(
                                      current['preferredLanguages'])
                                  .join(' · '),
                              color: GixbeeTheme.accentTeal,
                            ),
                          ],
                          if (totalRequests > 1) ...[
                            const SizedBox(height: 12),
                            _DetailCard(
                              icon: Icons.info_outline_rounded,
                              label: 'Queue note',
                              value:
                                  'Accepting this cancels your other ${totalRequests - 1} pending request${totalRequests > 2 ? 's' : ''}',
                              color: GixbeeTheme.accentGold,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Action buttons (always visible above system nav) ───────────
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  // Decline button (semantic red — v106 press-scale)
                  Expanded(
                    child: GxPressable(
                      onTap: _isProcessing ? null : _declineCurrent,
                      child: Opacity(
                        opacity: _isProcessing ? 0.5 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: err),
                          ),
                          child: Text(
                            totalRequests > 1 ? 'Skip' : 'Decline',
                            style: TextStyle(
                                color: err,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Accept button (semantic green — v106 press-scale)
                  Expanded(
                    flex: 2,
                    child: GxPressable(
                      onTap: _isProcessing ? null : _accept,
                      child: Opacity(
                        opacity: _isProcessing ? 0.7 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: GixbeeTheme.accentGreen,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _isProcessing
                              ? SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      color: context.gx.onAccent,
                                      strokeWidth: 2.5),
                                )
                              : Text(
                                  'Accept Job',
                                  style: TextStyle(
                                      color: context.gx.onAccent,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail Card Widget ──────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: context.gx.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
