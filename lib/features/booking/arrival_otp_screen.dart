import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';
import 'completion_otp_screen.dart';

class ArrivalOtpScreen extends ConsumerStatefulWidget {
  final String bookingId;
  final String workerName;
  final String arrivalOtp;
  final bool isWorker;

  const ArrivalOtpScreen({
    super.key,
    required this.bookingId,
    required this.workerName,
    required this.arrivalOtp,
    this.isWorker = false,
  });

  @override
  ConsumerState<ArrivalOtpScreen> createState() => _ArrivalOtpScreenState();
}

class _ArrivalOtpScreenState extends ConsumerState<ArrivalOtpScreen>
    with SingleTickerProviderStateMixin {
  // ── Customer state ──────────────────────────────────────────
  bool _isRevealed = false; // hidden by default for security

  // ── Worker state ────────────────────────────────────────────
  bool _hasMarkedArrived = false;
  bool _isMarkingArrived = false;
  bool _isVerifying = false;

  late AnimationController _pulseController;
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
        AppConfig.bookingOtpLength, (_) => TextEditingController());
    _focusNodes =
        List.generate(AppConfig.bookingOtpLength, (_) => FocusNode());

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  // ── Mark arrived — triggers backend to generate arrivalOtp ──

  Future<void> _markArrived() async {
    setState(() => _isMarkingArrived = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .markArrived(widget.bookingId);
      setState(() => _hasMarkedArrived = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Arrival confirmed! Ask the customer for their OTP.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mark arrival: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingArrived = false);
    }
  }

  // ── Confirm arrival OTP (worker submits what customer told them) ──

  Future<void> _confirmArrival() async {
    final otpToVerify =
        _controllers.map((c) => c.text).join();

    if (otpToVerify.length != AppConfig.bookingOtpLength) {
      setState(() =>
          _errorMsg = 'Please enter all ${AppConfig.bookingOtpLength} digits');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMsg = null;
    });

    try {
      await ref.read(bookingRepositoryProvider).confirmArrival(
            bookingId: widget.bookingId,
            otp: otpToVerify,
          );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CompletionOtpScreen(
            bookingId: widget.bookingId,
            workerName: widget.workerName,
            isWorker: widget.isWorker,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Invalid OTP. Please try again.');
        for (final c in _controllers) {
          c.clear();
        }
        _focusNodes[0].requestFocus();
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
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
                                  alpha: 0.5 +
                                      _pulseController.value * 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.isWorker
                                ? 'At Location'
                                : 'Worker Arriving',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),

                const Spacer(flex: 2),

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

                Text(
                  'Arrival Verification',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isWorker
                      ? _hasMarkedArrived
                          ? 'Ask the customer for the arrival OTP\nand enter it below to begin the job.'
                          : 'Tap "I\'ve Arrived" when you reach\nthe service location.'
                      : '${widget.workerName} will arrive shortly.\nShare the OTP below when they arrive.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                // ── WORKER VIEW ─────────────────────────────
                if (widget.isWorker) ...[
                  if (!_hasMarkedArrived) ...[
                    // Step 1: Mark arrived
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isMarkingArrived ? null : _markArrived,
                        icon: _isMarkingArrived
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.location_on),
                        label: Text(
                          _isMarkingArrived
                              ? 'Confirming...'
                              : 'I\'ve Arrived at Location',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else ...[
                    // Step 2: Enter OTP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          AppConfig.bookingOtpLength, (i) {
                        return Container(
                          width: 60,
                          height: 68,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 6),
                          child: TextField(
                            controller: _controllers[i],
                            focusNode: _focusNodes[i],
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            maxLength: 1,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              counterText: '',
                              filled: true,
                              fillColor: _errorMsg != null
                                  ? Colors.red.withValues(alpha: 0.05)
                                  : colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: _errorMsg != null
                                      ? Colors.red
                                      : colorScheme.outlineVariant,
                                ),
                              ),
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: (value) {
                              setState(() => _errorMsg = null);
                              if (value.isNotEmpty &&
                                  i < AppConfig.bookingOtpLength - 1) {
                                _focusNodes[i + 1].requestFocus();
                              } else if (value.isEmpty && i > 0) {
                                // Backspace → move to previous field
                                _focusNodes[i - 1].requestFocus();
                              }
                              // No auto-submit — worker taps the button
                            },
                          ),
                        );
                      }),
                    ),
                    if (_errorMsg != null) ...[
                      const SizedBox(height: 12),
                      Text(_errorMsg!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13)),
                    ],
                  ],
                ],

                // ── CUSTOMER VIEW ───────────────────────────
                if (!widget.isWorker) ...[
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isRevealed = !_isRevealed),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 20),
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
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : [],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isRevealed ? 'TAP TO HIDE' : 'TAP TO REVEAL',
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
                            _isRevealed
                                ? (widget.arrivalOtp.isNotEmpty
                                    ? widget.arrivalOtp
                                    : '– – – –')
                                : '• • • •',
                            style: TextStyle(
                              color: _isRevealed
                                  ? Colors.white
                                  : colorScheme.onSurface,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.arrivalOtp.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Waiting for worker to mark arrival...',
                      style: TextStyle(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                          fontSize: 13),
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                Text(
                  widget.isWorker
                      ? 'Verify entry only after reaching the site'
                      : 'Only share this with the worker in person',
                  style: TextStyle(
                    color:
                        colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),

                const Spacer(flex: 3),

                // ── ACTION BUTTONS ──────────────────────────
                if (widget.isWorker && _hasMarkedArrived)
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
                                  color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(
                        _isVerifying ? 'Verifying...' : 'Start Job',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  )
                else if (!widget.isWorker)
                  const Text(
                    'Waiting for worker to confirm arrival...',
                    style: TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.grey),
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
