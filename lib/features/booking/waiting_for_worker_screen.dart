import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../shared/models/worker.dart';
import '../../shared/models/booking_status.dart';
import '../../core/config/app_config.dart';
import '../../services/socket_service.dart';
import 'live_tracking_map_screen.dart';
import 'no_workers_screen.dart';

class WaitingForWorkerScreen extends ConsumerStatefulWidget {
  final String bookingId;

  /// The pre-chosen pro for targeted requests — NULL for v126 broadcast
  /// requests ("first accept wins"), where the pro is only known once the
  /// status poll reports ACCEPTED (operatorName/operatorId in the payload).
  final Worker? worker;
  final String skill;

  /// How many pros the backend notified at broadcast time. Used only for
  /// copy; never gates whether this screen is shown.
  final int notifiedCount;

  /// Customer's ₹/hr budget for this request — shown on the summary card
  /// so the waiting screen answers "what exactly did I ask for?".
  final double? hourlyRate;

  /// Human-readable service location for the summary card.
  final String? locationLabel;

  const WaitingForWorkerScreen({
    super.key,
    required this.bookingId,
    this.worker,
    required this.skill,
    this.notifiedCount = 0,
    this.hourlyRate,
    this.locationLabel,
  });

  @override
  ConsumerState<WaitingForWorkerScreen> createState() =>
      _WaitingForWorkerScreenState();
}

class _WaitingForWorkerScreenState extends ConsumerState<WaitingForWorkerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  int _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds;
  Timer? _countdownTimer;
  StreamSubscription<Map<String, dynamic>>? _socketSub;
  bool _isAccepted = false;
  String? _arrivalOtp;

  /// Broadcast search wave. 1 = initial 90s fan-out; 2 = backend widened the
  /// radius and (maybe) notified more pros — the countdown restarts for the
  /// final window. Targeted requests (widget.worker != null) never enter
  /// wave 2: their single 90s window is authoritative.
  int _searchWave = 1;

  /// New pros pinged by the widened wave (from booking_search_expanded).
  int _wave2Notified = 0;

  /// Denominator for the countdown progress bar — reset when a new wave
  /// starts so the bar refills instead of jumping.
  int _waveTotalSeconds = AppConfig.jobAcceptTimeoutSeconds;

  /// Grace on top of the server window so the backend's own timeout (which
  /// cancels the booking and reaches us via socket/poll) normally wins — the
  /// local expiry is only the offline fallback.
  static const int _waveGraceSeconds = 15;

  // Broadcast requests: the claiming pro, learned from the accept poll.
  String? _acceptedName;
  String? _acceptedId;

  /// Billing snapshot loaded once on accept (rate / travel / est. petrol).
  double? _acceptedHourlyRate;
  double? _acceptDistanceKm;
  double? _estimatedPetrolAmount;
  double _petrolRatePerKm = 10;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _startCountdown();
    // Search-wave expansion is screen-specific. Booking acceptance flows
    // through the shared socket-backed status provider.
    _socketSub =
        ref.read(socketServiceProvider).notifications.listen(_onSocketEvent);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _countdownTimer?.cancel();
    _socketSub?.cancel();
    super.dispose();
  }

  void _onSocketEvent(Map<String, dynamic> data) {
    final event = data['_event'];
    final id = data['id']?.toString() ?? data['bookingId']?.toString();
    if (id != widget.bookingId) return;

    if (event == 'booking_search_expanded') {
      _enterSecondWave(
        (data['newWorkersNotified'] as num?)?.toInt() ?? 0,
      );
      return;
    }

  }

  /// Switch to the widened-search wave: restart the countdown for the final
  /// window instead of declaring "no workers" while the backend is still
  /// searching. Idempotent — the local timer expiry and the socket event can
  /// both trigger it in either order.
  void _enterSecondWave(int newWorkersNotified) {
    if (!mounted || _isAccepted || widget.worker != null) return;
    if (_searchWave >= 2) {
      // Already in wave 2 — just refresh the notified copy if it arrived late.
      if (newWorkersNotified > 0 && _wave2Notified == 0) {
        setState(() => _wave2Notified = newWorkersNotified);
      }
      return;
    }
    setState(() {
      _searchWave = 2;
      _wave2Notified = newWorkersNotified;
      _waveTotalSeconds =
          AppConfig.jobAcceptTimeoutSeconds + _waveGraceSeconds;
      _secondsRemaining = _waveTotalSeconds;
    });
  }

  Future<void> _cancelRequest() async {
    try {
      // If the worker already accepted but this UI was still on "searching",
      // refresh status and flip to the accepted view instead of cancelling.
      try {
        final live = await ref
            .read(bookingRepositoryProvider)
            .pollBookingStatus(widget.bookingId);
        final st =
            BookingStatus.fromString(live['status']?.toString() ?? '');
        if (st == BookingStatus.accepted || st.isActive) {
          _applyStatus(live);
          return;
        }
      } catch (_) {}

      await ref.read(bookingRepositoryProvider).cancelBooking(widget.bookingId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        // Cancel may fail if accept won the race — pull status again.
        try {
          final live = await ref
              .read(bookingRepositoryProvider)
              .pollBookingStatus(widget.bookingId);
          final st =
              BookingStatus.fromString(live['status']?.toString() ?? '');
          if (st == BookingStatus.accepted || st.isActive) {
            _applyStatus(live);
            return;
          }
        } catch (_) {}
        if (!mounted) return;
        showGxSnack(context, 'Failed to cancel: $e', type: GxSnackType.error);
      }
    }
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
        return;
      }

      // Broadcast wave 1 expired locally: the backend is widening the search
      // right now (its rebroadcast runs at the same 90s mark) — flip to the
      // final window even if the booking_search_expanded socket event was
      // missed. NEVER cancel here; that would kill the second wave.
      if (widget.worker == null && _searchWave < 2) {
        _enterSecondWave(0);
        return;
      }

      // Final window (or targeted request) expired with no news — the
      // backend timeout normally cancelled it already and told us via
      // socket/poll; this is the offline fallback. cancelBooking on an
      // already-CANCELLED booking is harmless.
      _countdownTimer?.cancel();
      if (mounted) {
        ref
            .read(bookingRepositoryProvider)
            .cancelBooking(widget.bookingId)
            .then((_) {}, onError: (_) {});
        _showNoWorkers();
      }
    });
  }

  void _applyStatus(Map<String, dynamic> statusData) {
    if (!mounted || _isAccepted) return;
    final status = BookingStatus.fromString(statusData['status'] ?? '');

    // Accept (or any post-accept live state if we missed the first push).
    if (status == BookingStatus.accepted ||
        status == BookingStatus.confirmed ||
        status == BookingStatus.arrived ||
        status == BookingStatus.active ||
        status == BookingStatus.inProgress) {
      _countdownTimer?.cancel();
      setState(() {
        _isAccepted = true;
        _arrivalOtp = statusData['arrivalOtp']?.toString();
        _acceptedName = statusData['operatorName']?.toString();
        _acceptedId = statusData['operatorId']?.toString();
        _acceptedHourlyRate ??= widget.hourlyRate;
        _applyBillingHints(statusData);
      });
      // Keep home / bookings lists fresh when the customer confirms.
      ref.invalidate(myBookingsProvider);
      unawaited(_loadAcceptedBilling());
    } else if (status == BookingStatus.cancelled ||
        status == BookingStatus.rejected) {
      _countdownTimer?.cancel();
      if (mounted) {
        _showNoWorkers();
      }
    }
  }

  void _applyBillingHints(Map<String, dynamic> data) {
    final rate = _readNum(
      data['hourlyRate'] ?? data['amount'] ?? widget.hourlyRate,
    );
    final dist = _readNum(data['acceptDistanceKm'] ?? data['petrolDistanceKm']);
    final petrolRate =
        _readNum(data['petrolRatePerKm']) ?? _petrolRatePerKm;
    final petrol =
        _readNum(data['estimatedPetrolAmount'] ?? data['petrolAmount']);
    if (rate != null && rate > 0) _acceptedHourlyRate = rate;
    if (petrolRate > 0) _petrolRatePerKm = petrolRate;
    if (dist != null && dist > 0) {
      _acceptDistanceKm = dist;
      _estimatedPetrolAmount = petrol ?? (dist * _petrolRatePerKm);
    }
  }

  Future<void> _loadAcceptedBilling() async {
    // Prefer full booking row — status cache may omit travel/petrol fields.
    final booking = await ref
        .read(bookingRepositoryProvider)
        .getBookingById(widget.bookingId);
    if (!mounted || booking == null) return;
    setState(() => _applyBillingHints(booking));
  }

  double? _readNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  void _showNoWorkers() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => NoWorkersScreen(skill: widget.skill)),
    );
  }

  /// The pro to show downstream: the pre-chosen one, or (broadcast) a
  /// minimal placeholder built from the accept poll payload.
  Worker get _effectiveWorker =>
      widget.worker ??
      Worker(
        id: _acceptedId ?? '',
        name: _acceptedName ?? 'Your pro',
        title: widget.skill,
        bio: '',
        imageUrl: '',
        rating: 0,
        completedJobs: 0,
        reviewCount: 0,
        isFeatured: false,
        hourlyRate: 0,
        skills: [widget.skill],
        availabilityTags: const [],
        primaryType: SkillType.manual,
        status: 'available',
      );

  void _confirmAndProceed() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveTrackingMapScreen(
          bookingId: widget.bookingId,
          worker: _effectiveWorker,
          arrivalOtp: _arrivalOtp,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Shared status stream: socket-first with a 5s Redis-backed fallback.
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      bookingStatusProvider(widget.bookingId),
      (_, next) {
        final data = next.value;
        if (data != null) _applyStatus(data);
      },
    );

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                if (!_isAccepted) ...[
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _searchWave >= 2
                          ? 'Widening the search…'
                          : 'Finding your ${widget.skill}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Hang tight — pros usually respond within a minute.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.gx.ink.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _summaryCard(),
                  const SizedBox(height: 14),
                  _statusTimeline(),
                  const SizedBox(height: 14),
                  _progressCard(),
                  const SizedBox(height: 14),
                  _reassuranceRow(),
                  const Spacer(),
                  GxButton(
                    label: 'Cancel Request',
                    onTap: _cancelRequest,
                    filled: false,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  const Spacer(flex: 2),
                  Icon(Icons.check_circle_rounded,
                      color: context.gx.accentSoft, size: 80),
                  const SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'Request Accepted!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: context.gx.card2,
                    backgroundImage: _effectiveWorker.imageUrl.isNotEmpty
                        ? NetworkImage(_effectiveWorker.imageUrl)
                        : null,
                    onBackgroundImageError: _effectiveWorker.imageUrl.isNotEmpty
                        ? (_, __) {}
                        : null,
                    child: _effectiveWorker.imageUrl.isEmpty
                        ? Text(
                            _effectiveWorker.name.isNotEmpty
                                ? _effectiveWorker.name[0]
                                : '?',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: context.gx.ink,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _effectiveWorker.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.gx.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Is on their way to your location',
                    style: TextStyle(
                      color: context.gx.ink.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _acceptedBillingCard(),
                  const Spacer(flex: 3),
                  GxButton(
                    label: 'Track on Map',
                    onTap: _confirmAndProceed,
                    icon: Icons.map_rounded,
                    fontSize: 16,
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Searching-state widgets ──────────────────────────────────────

  /// Rate + travel/petrol snapshot after a pro accepts.
  Widget _acceptedBillingCard() {
    final rate = _acceptedHourlyRate ?? widget.hourlyRate;
    final dist = _acceptDistanceKm;
    final petrol = _estimatedPetrolAmount;
    final hasRate = rate != null && rate > 0;
    final hasTravel = dist != null && dist > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.skill,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(height: 10),
          _acceptedBillingRow(
            Icons.schedule_rounded,
            'Work rate',
            hasRate
                ? '₹${rate.round()}/hr · 1 hr minimum'
                : 'Pay after the job (cash/UPI)',
          ),
          if (hasTravel) ...[
            const SizedBox(height: 8),
            _acceptedBillingRow(
              Icons.route_rounded,
              'Travel to you',
              '${dist.toStringAsFixed(dist >= 10 || dist == dist.roundToDouble() ? 0 : 1)} km one-way',
            ),
          ],
          if (petrol != null && petrol > 0) ...[
            const SizedBox(height: 8),
            _acceptedBillingRow(
              Icons.local_gas_station_rounded,
              'Est. petrol',
              '₹${petrol.round()} (₹${_petrolRatePerKm.round()}/km · final at completion)',
            ),
          ] else if (!hasTravel) ...[
            const SizedBox(height: 8),
            _acceptedBillingRow(
              Icons.local_gas_station_rounded,
              'Petrol',
              'Added from travel distance when the pro accepted',
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Final total = work time + petrol. Confirmed after the job.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: context.gx.ink.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptedBillingRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.gx.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: context.gx.ink.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: context.gx.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// What the customer asked for — skill, budget, place — so the wait
  /// screen answers "what exactly is being searched?" at a glance.
  Widget _summaryCard() {
    final rate = widget.hourlyRate;
    final loc = widget.locationLabel;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: context.gx.accentGradient),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.bolt_rounded,
                color: context.gx.onAccent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.skill,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: context.gx.ink)),
                const SizedBox(height: 3),
                Text(
                  rate != null && rate > 0
                      ? '₹${rate.round()}/hr budget · 1 hr minimum'
                      : 'Instant request · pay after the job',
                  style: TextStyle(
                      fontSize: 12,
                      color: context.gx.ink.withValues(alpha: 0.55)),
                ),
                if (loc != null && loc.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined,
                          size: 13, color: context.gx.accentSoft),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          loc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              color:
                                  context.gx.ink.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Live order-tracking timeline — replaces the abstract radar with the
  /// request's ACTUAL story: placed → pros notified (→ area widened) →
  /// waiting for an accept.
  Widget _statusTimeline() {
    final steps = <({String title, String sub, bool done, bool active})>[
      (
        title: 'Request placed',
        sub: 'Sent to the Gixbee network',
        done: true,
        active: false,
      ),
      (
        title: widget.notifiedCount > 0
            ? '${widget.notifiedCount} nearby pro${widget.notifiedCount == 1 ? '' : 's'} notified'
            : 'Notifying nearby pros',
        sub: widget.notifiedCount > 0
            ? '${widget.skill} pros around you got an alert'
            : 'Matching your request right now',
        done: widget.notifiedCount > 0,
        active: widget.notifiedCount == 0 && _searchWave < 2,
      ),
      if (_searchWave >= 2)
        (
          title: 'Search area expanded',
          sub: _wave2Notified > 0
              ? '$_wave2Notified more pro${_wave2Notified == 1 ? '' : 's'} notified slightly farther away'
              : 'Looking a little farther away',
          done: true,
          active: false,
        ),
      (
        title: 'Waiting for a pro to accept',
        sub: 'First to accept gets your job',
        done: false,
        active: true,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _timelineRow(steps[i], isLast: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _timelineRow(
    ({String title, String sub, bool done, bool active}) s, {
    required bool isLast,
  }) {
    final green = context.gx.accentSoft;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              s.active
                  ? AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) {
                        final halo = 0.5 +
                            0.5 *
                                math.sin(
                                    2 * math.pi * _pulseController.value);
                        return Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: green.withValues(
                                alpha: 0.12 + 0.20 * halo),
                          ),
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: green),
                          ),
                        );
                      },
                    )
                  : Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: s.done ? green : Colors.transparent,
                        border: s.done
                            ? null
                            : Border.all(
                                color: context.gx.border, width: 2),
                      ),
                      child: s.done
                          ? Icon(Icons.check_rounded,
                              size: 14, color: context.gx.onAccent)
                          : null,
                    ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: s.done
                        ? green.withValues(alpha: 0.5)
                        : context.gx.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 6 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(s.title,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: context.gx.ink)),
                      ),
                      if (s.active) _animatedDots(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(s.sub,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: context.gx.ink.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "…" that breathes beside the active step.
  Widget _animatedDots() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, _) {
        final t = _pulseController.value * 3;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Opacity(
                  opacity: 0.25 +
                      0.75 *
                          (0.5 +
                                  0.5 *
                                      math.sin(2 *
                                          math.pi *
                                          (t - i * 0.33)))
                              .clamp(0.0, 1.0),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.gx.accentSoft),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Countdown as a draining bar with the exact time — honest about the
  /// window, and it visibly REFILLS when the widened second wave starts.
  Widget _progressCard() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final label = minutes > 0
        ? '${minutes}m ${seconds.toString().padLeft(2, '0')}s'
        : '${_secondsRemaining}s';
    final frac = _waveTotalSeconds <= 0
        ? 0.0
        : (_secondsRemaining / _waveTotalSeconds).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 16, color: context.gx.accentSoft),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink)),
              const SizedBox(width: 4),
              Text('left in this search',
                  style: TextStyle(
                      fontSize: 12,
                      color: context.gx.ink.withValues(alpha: 0.5))),
              const Spacer(),
              Text(
                widget.worker != null
                    ? 'Direct request'
                    : _searchWave >= 2
                        ? 'Final window'
                        : 'Auto-widens after this',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.gx.accentSoft),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 6,
              backgroundColor: context.gx.border,
              valueColor: AlwaysStoppedAnimation(context.gx.accentSoft),
            ),
          ),
        ],
      ),
    );
  }

  /// Two calm facts that answer the two biggest mid-wait anxieties.
  Widget _reassuranceRow() {
    Widget chip(IconData icon, String text) => Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: context.gx.accentSoft.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: context.gx.accentSoft.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 15, color: context.gx.accentSoft),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color:
                              context.gx.ink.withValues(alpha: 0.7))),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        chip(Icons.verified_user_outlined,
            'Cancelling is free until a pro accepts'),
        const SizedBox(width: 10),
        chip(Icons.payments_outlined,
            'Pay the pro directly after the job'),
      ],
    );
  }
}

