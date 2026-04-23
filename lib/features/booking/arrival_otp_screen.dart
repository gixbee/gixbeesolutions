import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import 'completion_otp_screen.dart';

/// Gate 1 of the live flow.
/// The customer reads this OTP aloud; the worker types it in their app.
/// Once verified, the booking status moves from ACCEPTED → ACTIVE.
class ArrivalOtpScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String workerName;
  final String arrivalOtp; // the 4-digit OTP the backend generated

  const ArrivalOtpScreen({
    super.key,
    required this.bookingId,
    required this.workerName,
    required this.arrivalOtp,
  });

  @override
  ConsumerState<ArrivalOtpScreen> createState() => _ArrivalOtpScreenState();
}

class _ArrivalOtpScreenState extends ConsumerState<ArrivalOtpScreen>
    with SingleTickerProviderStateMixin {
  bool _isRevealed = false;
  bool _isVerifying = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _confirmArrival() async {
    setState(() => _isVerifying = true);
    try {
      // Tell the backend the worker has arrived
      await ref.read(bookingRepositoryProvider).confirmArrival(
            bookingId: widget.bookingId,
            otp: widget.arrivalOtp,
          );

      if (!mounted) return;

      // Navigate to the Completion OTP screen (gate 2)
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompletionOtpScreen(
            bookingId: widget.bookingId,
            workerName: widget.workerName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Top bar
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (_, __) => Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.orange.withValues(
                                  alpha: 0.5 + _pulseController.value * 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Worker Arriving',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48), // balance the back button
                  ],
                ),

                const Spacer(flex: 2),

                // Icon
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.directions_walk_rounded,
                    size: 56,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'Arrival Verification',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.workerName} has reached your location.\nShare this OTP to confirm arrival.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                // OTP display card
                GestureDetector(
                  onTap: () => setState(() => _isRevealed = !_isRevealed),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: _isRevealed
                          ? colorScheme.primary
                          : colorScheme.surfaceContainerHighest,
                      border: Border.all(
                        color: _isRevealed
                            ? colorScheme.primary
                            : colorScheme.outlineVariant,
                        width: 2,
                      ),
                      boxShadow: _isRevealed
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      children: [
                        Text(
                          _isRevealed ? 'ARRIVAL OTP' : 'TAP TO REVEAL',
                          style: TextStyle(
                            color: _isRevealed
                                ? Colors.white.withValues(alpha: 0.7)
                                : colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isRevealed ? widget.arrivalOtp : '• • • •',
                          style: TextStyle(
                            color: _isRevealed ? Colors.white : colorScheme.onSurface,
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 16,
                          ),
                        ),
                        if (_isRevealed) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: widget.arrivalOtp));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('OTP copied'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy, size: 14, color: Colors.white70),
                                SizedBox(width: 4),
                                Text(
                                  'Copy',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Text(
                  'Only share this with the worker in person',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),

                const Spacer(flex: 3),

                // Confirm button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _isVerifying ? null : _confirmArrival,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      _isVerifying ? 'Verifying...' : 'Worker Has Arrived',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

