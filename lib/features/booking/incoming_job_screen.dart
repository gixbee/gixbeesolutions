import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';

class IncomingJobScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> bookingData;

  const IncomingJobScreen({super.key, required this.bookingData});

  @override
  ConsumerState<IncomingJobScreen> createState() => _IncomingJobScreenState();
}

class _IncomingJobScreenState extends ConsumerState<IncomingJobScreen> {
  late int _secondsRemaining;
  Timer? _timer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = AppConfig.jobAcceptTimeoutSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
        // Auto-decline on timeout — notify backend
        _declineJob(autoTimeout: true);
      }
    });
  }

  Future<void> _acceptJob() async {
    setState(() => _isProcessing = true);
    _timer?.cancel();
    try {
      final bookingId = widget.bookingData['id'] as String?;
      if (bookingId == null) throw Exception('Missing booking ID');

      await ref.read(bookingRepositoryProvider).acceptBooking(bookingId);

      if (mounted) {
        Navigator.pop(context, true); // return accepted=true
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job Accepted! Head to the location.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept job: $e')),
        );
        _startTimer(); // restart timer if accept fails
      }
    }
  }

  Future<void> _declineJob({bool autoTimeout = false}) async {
    _timer?.cancel();
    setState(() => _isProcessing = true);
    try {
      final bookingId = widget.bookingData['id'] as String?;
      if (bookingId != null) {
        // Notify backend so it can re-assign to another worker immediately
        await ref
            .read(bookingRepositoryProvider)
            .updateBookingStatus(bookingId, 'REJECTED');
      }
    } catch (e) {
      debugPrint('[IncomingJob] Decline notify failed: $e');
    } finally {
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final customerName =
        widget.bookingData['customer_name'] as String? ?? 'New Customer';
    final skill = widget.bookingData['skill'] as String? ?? 'General Help';
    final location =
        widget.bookingData['serviceLocation'] as String? ?? 'Nearby';
    final amount =
        (widget.bookingData['amount'] as num?)?.toDouble() ?? 0.0;
    final timerFraction =
        _secondsRemaining / AppConfig.jobAcceptTimeoutSeconds;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'INSTANT HELP REQUEST',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              // Countdown ring
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: timerFraction,
                      strokeWidth: 8,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest,
                      color: _secondsRemaining > 10
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  Text(
                    '$_secondsRemaining',
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              Text(customerName,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('needs a $skill',
                  style: TextStyle(
                      fontSize: 18, color: colorScheme.secondary)),
              const SizedBox(height: 32),

              _buildInfoRow(Icons.location_on, location, colorScheme),
              const SizedBox(height: 16),
              _buildInfoRow(Icons.payments,
                  'Estimated: ₹${amount.toInt()}', colorScheme),

              const Spacer(),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing
                          ? null
                          : () => _declineJob(),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red),
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          _isProcessing ? null : _acceptJob,
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Accept Job',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
      ],
    );
  }
}
