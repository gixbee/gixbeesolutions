import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/models/worker.dart';
import '../../shared/models/booking_status.dart';
import '../../core/config/app_config.dart';
import 'arrival_otp_screen.dart';

class WaitingForWorkerScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final Worker worker;
  final String skill;

  const WaitingForWorkerScreen({
    super.key,
    required this.bookingId,
    required this.worker,
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
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
           _showError('No worker accepted your request in time. Please try again later.');
           // Optional: call _cancelRequest() if you want to ensure backend cancellation
           ref.read(bookingRepositoryProvider).cancelBooking(widget.bookingId).catchError((_) {});
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
          });
        } else if (status == BookingStatus.cancelled || status == BookingStatus.rejected) {
          _pollingTimer?.cancel();
          _countdownTimer?.cancel();
          if (mounted) {
            _showError('Request was not accepted or timed out.');
          }
        }
      } catch (e) {
        debugPrint('Polling failed: $e');
      }
    });
  }

  void _showError(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Request Status'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  void _confirmAndProceed() {
    // Issue #22: Error state instead of silently falling back to '0000'
    if (_arrivalOtp == null) {
      _showError('OTP not received. Please contact support.');
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ArrivalOtpScreen(
          bookingId: widget.bookingId,
          workerName: widget.worker.name,
          arrivalOtp: _arrivalOtp!,
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
                'Waiting for ${widget.worker.name} to accept your request',
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              _buildTimerWidget(colorScheme),
              const SizedBox(height: 40),
              OutlinedButton(
                onPressed: _cancelRequest,
                child: const Text('Cancel Request'),
              ),
            ] else ...[
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 24),
              const Text(
                'Request Accepted!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              CircleAvatar(
                radius: 40,
                backgroundImage: NetworkImage(widget.worker.imageUrl),
              ),
              const SizedBox(height: 16),
              Text(
                widget.worker.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Is on their way to your location',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmAndProceed,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                  child: const Text('Confirm & See OTP', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
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
                    color: colorScheme.primary.withValues(alpha: 1 - _pulseController.value),
                    width: 2,
                  ),
                ),
              ),
            CircleAvatar(
              radius: 40,
              backgroundColor: colorScheme.primary,
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

