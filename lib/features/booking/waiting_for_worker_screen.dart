import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/models/worker.dart';
import '../../shared/models/booking_status.dart';
import '../../core/config/app_config.dart';
import 'live_tracking_map_screen.dart';
import 'no_workers_screen.dart';

class WaitingForWorkerScreen extends ConsumerStatefulWidget {
  final String bookingId;

  /// The pre-chosen pro for targeted requests — NULL for v126 broadcast
  /// requests ("first accept wins"), where the pro is only known once the
  /// status poll reports ACCEPTED (operatorName/operatorId in the payload).
  final Worker? worker;
  final String skill;

  const WaitingForWorkerScreen({
    super.key,
    required this.bookingId,
    this.worker,
    required this.skill,
  });

  @override
  ConsumerState<WaitingForWorkerScreen> createState() => _WaitingForWorkerScreenState();
}

class _WaitingForWorkerScreenState extends ConsumerState<WaitingForWorkerScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  Timer? _pollingTimer;
  int _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds;
  Timer? _countdownTimer;
  bool _isAccepted = false;
  String? _arrivalOtp;

  // Broadcast requests: the claiming pro, learned from the accept poll.
  String? _acceptedName;
  String? _acceptedId;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startCountdown();
    _startPolling();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
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
      } else {
        _countdownTimer?.cancel();
        _pollingTimer?.cancel();
        if (mounted) {
          // Make sure the stale request is cancelled server-side, then show
          // the v126 "no pros available" fallback with real next steps.
          ref
              .read(bookingRepositoryProvider)
              .cancelBooking(widget.bookingId)
              .then((_) {}, onError: (_) {});
          _showNoWorkers();
        }
      }
    });
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: AppConfig.bookingPollIntervalSeconds), (timer) async {
      try {
        final statusData = await ref.read(bookingRepositoryProvider).pollBookingStatus(widget.bookingId);
        final status = BookingStatus.fromString(statusData['status'] ?? '');

        if (status == BookingStatus.accepted) {
          _pollingTimer?.cancel();
          _countdownTimer?.cancel();
          setState(() {
            _isAccepted = true;
            _arrivalOtp = statusData['arrivalOtp'];
            _acceptedName = statusData['operatorName']?.toString();
            _acceptedId = statusData['operatorId']?.toString();
          });
        } else if (status == BookingStatus.cancelled || status == BookingStatus.rejected) {
          _pollingTimer?.cancel();
          _countdownTimer?.cancel();
          if (mounted) {
            _showNoWorkers();
          }
        }
      } catch (e) {
        debugPrint('Polling failed: $e');
      }
    });
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
    // Navigate to live tracking map
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isAccepted) ...[
              _buildRadarAnimation(colorScheme),
              const SizedBox(height: 40),
              Text(
                'Searching for ${widget.skill}...',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                widget.worker != null
                    ? 'Waiting for ${widget.worker!.name} to accept your request'
                    : 'All nearby ${widget.skill} pros have been notified — the first to accept gets assigned',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              _buildTimerWidget(colorScheme),
              const SizedBox(height: 40),
              GxButton(
                label: 'Cancel Request',
                onTap: _cancelRequest,
                filled: false,
                expand: false,
              ),
            ] else ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 24),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Request Accepted!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              CircleAvatar(
                radius: 40,
                backgroundImage: _effectiveWorker.imageUrl.isNotEmpty
                    ? NetworkImage(_effectiveWorker.imageUrl)
                    : null,
                onBackgroundImageError:
                    _effectiveWorker.imageUrl.isNotEmpty ? (_, __) {} : null,
                child: _effectiveWorker.imageUrl.isEmpty
                    ? Text(
                        _effectiveWorker.name.isNotEmpty
                            ? _effectiveWorker.name[0]
                            : '?',
                        style: const TextStyle(fontSize: 24))
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                _effectiveWorker.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Is on their way to your location',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              GxButton(
                label: 'Track on Map',
                onTap: _confirmAndProceed,
                icon: Icons.map_rounded,
                fontSize: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadarAnimation(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 0; i < 3; i++)
              Container(
                width: 100 + (i * 50 * _pulseController.value),
                height: 100 + (i * 50 * _pulseController.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.gx.accent.withValues(alpha: 1 - _pulseController.value),
                    width: 2,
                  ),
                ),
              ),
            CircleAvatar(
              radius: 40,
              backgroundColor: context.gx.accent,
              child: const Icon(Icons.flash_on, color: Colors.white, size: 40),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimerWidget(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, size: 18),
          const SizedBox(width: 8),
          Text(
            '$_secondsRemaining s',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

