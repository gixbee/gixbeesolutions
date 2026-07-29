import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/worker_repository.dart';
import '../../services/socket_service.dart';
import '../../services/location_service.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../theme.dart';
import '../billing/job_pack_screen.dart';

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
  Timer? _pollTimer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requests = [widget.bookingData];
    unawaited(_loadMyPosition());
    _startTimer();
    Future.delayed(const Duration(seconds: 2), _pollForMoreRequests);
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollForMoreRequests());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Phone unlocked: re-sync the countdown from the wall clock right now.
      // Requests that expired while locked are auto-declined instead of
      // showing a frozen timer that errors on Accept.
      _tick();
      unawaited(_pollForMoreRequests());
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

  // ── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();

    // Deadline = createdAt + timeout when the server timestamp is available
    // (so time spent locked/backgrounded counts against the window), else
    // now + timeout.
    var deadline = DateTime.now()
        .add(Duration(seconds: AppConfig.jobAcceptTimeoutSeconds));
    if (_requests.isNotEmpty && _currentIndex < _requests.length) {
      final currentRequest = _requests[_currentIndex];
      final createdAt =
          DateTime.tryParse('${currentRequest['createdAt'] ?? ''}')?.toLocal();
      if (createdAt != null) {
        deadline =
            createdAt.add(Duration(seconds: AppConfig.jobAcceptTimeoutSeconds));
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

  // ── Poll for more requests while screen is open ───────────────────────────

  Future<void> _pollForMoreRequests() async {
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
      });
    } catch (e) {
      debugPrint('[IncomingJob] Poll merge failed: $e');
    }
  }

  // ── Accept ────────────────────────────────────────────────────────────────

  Future<void> _accept() async {
    if (_isProcessing || _requests.isEmpty) return;
    setState(() => _isProcessing = true);
    _timer?.cancel();

    final current = _requests[_currentIndex];
    final bookingId = current['id'] as String?;

    try {
      if (bookingId == null) throw Exception('Missing booking ID');
      await ref.read(bookingRepositoryProvider).acceptBooking(bookingId);

      if (!mounted) return;

      // Start streaming worker's location to the customer
      final user = await ref.read(currentUserProvider.future);
      if (user != null) {
        ref.read(socketServiceProvider).startLocationStream(user.id, bookingId);
        // Seed Redis immediately so customer status-poll can show a pin
        // before the first GPS stream tick arrives.
        try {
          final pos =
              await ref.read(locationServiceProvider).getCurrentPosition();
          if (pos != null) {
            await ref.read(workerRepositoryProvider).updateMyLocation(
                  lat: pos.latitude,
                  lng: pos.longitude,
                );
          }
        } catch (_) {}
      }
      if (!mounted) return; // re-check: awaited currentUserProvider above

      // So Home's active-job card appears immediately (not only after pull-refresh).
      ref.invalidate(myBookingsProvider);

      // Backend auto-cancels all other pending bookings for this worker
      Navigator.pop(context, {'accepted': true, 'bookingId': bookingId});
      showGxSnack(
        context,
        'Job Accepted! Head to the customer location.',
        type: GxSnackType.success,
        duration: const Duration(seconds: 4),
      );
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
        Navigator.pop(context, {
          'accepted': false,
          'declinedIds': List<String>.from(_declinedIds),
        });
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const JobPackScreen()),
        );
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
    final bookingId = _requests[_currentIndex]['id'] as String?;
    try {
      if (bookingId != null) {
        await ref.read(bookingRepositoryProvider).rejectBooking(bookingId);
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

    final colorScheme = Theme.of(context).colorScheme;
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
      backgroundColor: colorScheme.surface,
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
                    icon: const Icon(Icons.close),
                    onPressed: _isProcessing ? null : _dismissAll,
                  ),
                  const Spacer(),
                  // Queue indicator badge
                  if (totalRequests > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$totalRequests requests waiting',
                            style: const TextStyle(
                              color: Colors.white,
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
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flash_on, color: Colors.orange, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'INSTANT REQUEST',
                            style: TextStyle(
                                color: Colors.orange,
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
                          color: isActive
                              ? context.gx.accent
                              : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isActive
                                ? context.gx.accent
                                : colorScheme.outlineVariant,
                          ),
                        ),
                        child: Text(
                          req['customer_name'] as String? ?? 'Request ${i + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : null,
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

            const Spacer(),

            // ── Countdown ring ──────────────────────────────────────────────
            // Single coherent a11y label for the countdown — without this a
            // screen reader reads the ring's two visual Text nodes as the
            // disjoint "36" then "seconds", plus the progress indicator's raw
            // percentage. ExcludeSemantics suppresses those noisy inner nodes.
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
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: _secondsRemaining > 20
                        ? Colors.green
                        : _secondsRemaining > 10
                            ? Colors.orange
                            : Colors.red,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_secondsRemaining',
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'seconds',
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ── Customer info ───────────────────────────────────────────────
            Text(
              customerName,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'needs a $skill',
              style: TextStyle(
                  fontSize: 17, color: colorScheme.secondary),
            ),

            const SizedBox(height: 28),

            // ── Details cards ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  _DetailCard(
                    icon: Icons.location_on_rounded,
                    label: 'Location',
                    value: locationLine,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  _DetailCard(
                    icon: Icons.payments_rounded,
                    label: isHourlyRate ? "Customer's Rate" : 'Job Amount',
                    value: isHourlyRate
                        ? '₹${amount.toStringAsFixed(0)}/hr · 1 hr minimum'
                        : '₹${amount.toStringAsFixed(0)}',
                    color: Colors.green,
                  ),
                  // Uber-style broadcast requests carry the customer's issue
                  // description — show it so the pro can decide before accepting.
                  if ((current['description'] as String?)?.isNotEmpty ??
                      false) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      icon: Icons.description_outlined,
                      label: 'Issue',
                      value: current['description'] as String,
                      color: context.gx.accentSoft,
                    ),
                  ],
                  // v126 language step: the customer's required languages.
                  if ((current['preferredLanguages'] as List?)?.isNotEmpty ??
                      false) ...[
                    const SizedBox(height: 12),
                    _DetailCard(
                      icon: Icons.translate_rounded,
                      label: 'Customer speaks',
                      value: (current['preferredLanguages'] as List)
                          .map((e) => e.toString())
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
                      color: Colors.orange,
                    ),
                  ],
                ],
              ),
            ),

            const Spacer(),

            // ── Action buttons ──────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                            border: Border.all(color: Colors.red),
                          ),
                          child: Text(
                            totalRequests > 1 ? 'Skip' : 'Decline',
                            style: const TextStyle(
                                color: Colors.red,
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
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Accept Job',
                                  style: TextStyle(
                                      color: Colors.white,
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
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
