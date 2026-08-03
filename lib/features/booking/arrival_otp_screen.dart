import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import 'completion_otp_screen.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';

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

    if (!widget.isWorker) {
      _checkInitialStatus();
    }
  }

  Future<void> _checkInitialStatus() async {
    try {
      final b = await ref.read(bookingRepositoryProvider).getBookingById(widget.bookingId);
      if (b != null && mounted) {
        final status = b['status']?.toString().toUpperCase();
        if (status == 'ACTIVE' || status == 'IN_PROGRESS' || status == 'COMPLETED') {
          _transitionToNextScreen();
        }
      }
    } catch (e) {
      debugPrint('Error checking initial status on ArrivalOtpScreen: $e');
    }
  }

  bool _navigatingAway = false;

  void _watchArrivalForCustomer() {
    if (widget.isWorker || _navigatingAway) return;
    ref.listen<AsyncValue<Map<String, dynamic>>>(
      bookingStatusProvider(widget.bookingId),
      (prev, next) {
        final status = next.value?['status']?.toString().toUpperCase();
        if (status == 'ACTIVE' || status == 'IN_PROGRESS' || status == 'COMPLETED') {
          _transitionToNextScreen();
        }
      },
    );
  }

  void _transitionToNextScreen() {
    if (_navigatingAway || !mounted) return;
    _navigatingAway = true;
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

  // ── Mark arrived — notifies the customer (FCM push containing the
  // arrivalOtp that was generated at booking creation). Does NOT generate
  // a new OTP; it just announces arrival and unlocks the OTP entry below.

  Future<void> _markArrived() async {
    setState(() => _isMarkingArrived = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .markArrived(widget.bookingId);
      setState(() => _hasMarkedArrived = true);
      if (mounted) {
        showGxSnack(
          context,
          'Customer notified! Ask them for the 4-digit arrival OTP.',
          type: GxSnackType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Failed to mark arrival: $e',
            type: GxSnackType.error);
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
    _watchArrivalForCustomer();
    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final err = Theme.of(context).colorScheme.error;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              gx.accent.withValues(alpha: 0.25),
              gx.bg,
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
                      icon: Icon(Icons.arrow_back, color: gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.gx.accent.withValues(alpha: 0.15),
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
                                color: context.gx.accent.withValues(
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
                            style: TextStyle(
                              color: context.gx.accent,
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
                    color: context.gx.accent.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.directions_walk_rounded,
                    size: 56,
                    color: context.gx.accent,
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
                          ? 'Enter the arrival OTP provided by the customer to start the job.'
                          : 'Tap "I Have Arrived" to notify the customer. They will share the arrival OTP with you.'
                      : '${widget.workerName} will arrive shortly.\nShare the OTP below when they arrive.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: muted,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 32),

                // ── WORKER VIEW ─────────────────────────────
                if (widget.isWorker) ...[
                  if (!_hasMarkedArrived) ...[
                    // Step 1: Mark arrived
                    GxButton(
                      label: 'I Have Arrived',
                      onTap: _markArrived,
                      icon: Icons.location_on,
                      loading: _isMarkingArrived,
                      height: 56,
                      fontSize: 16,
                    ),
                  ] else ...[
                    // Step 2: Enter OTP
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                          AppConfig.bookingOtpLength, (i) {
                        final filledBox =
                            _controllers[i].text.isNotEmpty;
                        // Per-state borders: the app's
                        // inputDecorationTheme overrides a bare `border`
                        // with a borderless enabled/focused state.
                        OutlineInputBorder boxBorder(
                                Color color, double w) =>
                            OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  BorderSide(color: color, width: w),
                            );
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
                            style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: gx.ink),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              filled: true,
                              fillColor: _errorMsg != null
                                  ? err.withValues(alpha: 0.08)
                                  : filledBox
                                      ? gx.accent.withValues(alpha: 0.10)
                                      : gx.card,
                              enabledBorder: boxBorder(
                                _errorMsg != null
                                    ? err
                                    : filledBox
                                        ? gx.accent
                                        : gx.ink.withValues(alpha: 0.25),
                                1.5,
                              ),
                              focusedBorder: boxBorder(
                                  _errorMsg != null ? err : gx.accent, 2),
                              errorBorder: boxBorder(err, 1.5),
                              focusedErrorBorder: boxBorder(err, 2),
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
                          style: TextStyle(color: err, fontSize: 13)),
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
                        color: _isRevealed ? gx.accent : gx.card2,
                        border: Border.all(
                          color: _isRevealed ? gx.accent : gx.border,
                          width: 2,
                        ),
                        boxShadow: _isRevealed
                            ? [
                                BoxShadow(
                                  color: gx.accent.withValues(alpha: 0.3),
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
                                  ? gx.onAccent.withValues(alpha: 0.7)
                                  : muted,
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
                              color: _isRevealed ? gx.onAccent : gx.ink,
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
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ],

                const SizedBox(height: 12),
                Text(
                  widget.isWorker
                      ? 'Verify entry only after reaching the site'
                      : 'Only share this with the worker in person',
                  style: TextStyle(color: muted, fontSize: 12),
                ),

                const Spacer(flex: 3),

                // ── ACTION BUTTONS ──────────────────────────
                if (widget.isWorker && _hasMarkedArrived)
                  GxButton(
                    label: 'Start Job',
                    onTap: _confirmArrival,
                    icon: Icons.check_circle_outline,
                    loading: _isVerifying,
                    height: 56,
                    fontSize: 16,
                  )
                else if (!widget.isWorker)
                  Text(
                    'Waiting for worker to confirm arrival...',
                    style: TextStyle(
                        fontStyle: FontStyle.italic, color: muted),
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
