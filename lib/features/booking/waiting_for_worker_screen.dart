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

  const WaitingForWorkerScreen({
    super.key,
    required this.bookingId,
    this.worker,
    required this.skill,
    this.notifiedCount = 0,
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

  /// Grace on top of the server window so the backend's own timeout (which
  /// cancels the booking and reaches us via socket/poll) normally wins — the
  /// local expiry is only the offline fallback.
  static const int _waveGraceSeconds = 15;

  // Broadcast requests: the claiming pro, learned from the accept poll.
  String? _acceptedName;
  String? _acceptedId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _startCountdown();
    // Primary: Socket.IO booking_accepted. Fallback: shared status provider
    // (30s Redis-backed poll) — no extra 5s timer.
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

    if (event != 'booking_accepted') return;
    _applyStatus({
      'status': data['status'] ?? 'ACCEPTED',
      'arrivalOtp': data['arrivalOtp'],
      'operatorName': data['operatorName'],
      'operatorId': data['operatorId'],
    });
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
      _secondsRemaining =
          AppConfig.jobAcceptTimeoutSeconds + _waveGraceSeconds;
    });
  }

  Future<void> _cancelRequest() async {
    try {
      await ref.read(bookingRepositoryProvider).cancelBooking(widget.bookingId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
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

    if (status == BookingStatus.accepted) {
      _countdownTimer?.cancel();
      setState(() {
        _isAccepted = true;
        _arrivalOtp = statusData['arrivalOtp']?.toString();
        _acceptedName = statusData['operatorName']?.toString();
        _acceptedId = statusData['operatorId']?.toString();
      });
      // Keep home / bookings lists fresh when the customer confirms.
      ref.invalidate(myBookingsProvider);
    } else if (status == BookingStatus.cancelled ||
        status == BookingStatus.rejected) {
      _countdownTimer?.cancel();
      if (mounted) {
        _showNoWorkers();
      }
    }
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

  String get _searchSubtitle {
    if (widget.worker != null) {
      return 'Waiting for ${widget.worker!.name} to accept your request';
    }
    if (_searchWave >= 2) {
      return _wave2Notified > 0
          ? 'Expanded the search area — notified $_wave2Notified more '
              '${widget.skill} pro${_wave2Notified == 1 ? '' : 's'} slightly '
              'farther away'
          : 'Expanded the search area — still looking for an available pro';
    }
    if (widget.notifiedCount > 0) {
      return 'Notified ${widget.notifiedCount} nearby '
          '${widget.skill} pro${widget.notifiedCount == 1 ? '' : 's'} — '
          'the first to accept gets assigned';
    }
    return 'Looking for nearby ${widget.skill} pros who can help right now';
  }

  @override
  Widget build(BuildContext context) {
    // Fallback status stream (30s, Redis-backed) — socket/FCM are primary.
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
                const Spacer(flex: 2),
                if (!_isAccepted) ...[
                  _buildRadarAnimation(),
                  const SizedBox(height: 36),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _searchWave >= 2
                          ? 'Widening the search…'
                          : 'Searching for ${widget.skill}…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: context.gx.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _searchSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: context.gx.ink.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildTimerWidget(),
                  const SizedBox(height: 12),
                  Text(
                    'Stay on this screen — we\'ll notify you when a pro accepts',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.gx.ink.withValues(alpha: 0.45),
                    ),
                  ),
                  const Spacer(flex: 3),
                  GxButton(
                    label: 'Cancel Request',
                    onTap: _cancelRequest,
                    filled: false,
                  ),
                  const SizedBox(height: 16),
                ] else ...[
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

  Widget _buildRadarAnimation() {
    const size = 220.0;
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(size, size),
            painter: _SearchRadarPainter(
              progress: _pulseController.value,
              accent: context.gx.accent,
              accentSoft: context.gx.accentSoft,
            ),
            child: Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: context.gx.accentGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: context.gx.accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 36),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimerWidget() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    final label = minutes > 0
        ? '${minutes}m ${seconds.toString().padLeft(2, '0')}s'
        : '${_secondsRemaining}s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.gx.card2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.gx.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 18, color: context.gx.accentSoft),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.gx.ink,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'remaining',
            style: TextStyle(
              fontSize: 12.5,
              color: context.gx.ink.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanding radar rings + a sweeping arc — reads as “searching nearby”, not
/// a generic spinner.
class _SearchRadarPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color accentSoft;

  _SearchRadarPainter({
    required this.progress,
    required this.accent,
    required this.accentSoft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Soft fill disc behind the rings.
    canvas.drawCircle(
      center,
      maxR * 0.92,
      Paint()
        ..color = accent.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );

    // Three staggered expanding rings.
    for (var i = 0; i < 3; i++) {
      final t = (progress + i / 3) % 1.0;
      final radius = 36 + t * (maxR - 40);
      final alpha = (1.0 - t).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = accent.withValues(alpha: 0.15 + alpha * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }

    // Sweeping radar wedge.
    final sweepAngle = progress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 0.9,
        endAngle: sweepAngle,
        colors: [
          accentSoft.withValues(alpha: 0.0),
          accentSoft.withValues(alpha: 0.28),
        ],
        transform: GradientRotation(sweepAngle - 0.9),
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR * 0.88, sweepPaint);

    // Outer guide ring.
    canvas.drawCircle(
      center,
      maxR * 0.88,
      Paint()
        ..color = accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SearchRadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accent != accent ||
      oldDelegate.accentSoft != accentSoft;
}
