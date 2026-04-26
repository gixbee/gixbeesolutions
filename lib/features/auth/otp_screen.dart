import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../../services/notification_service.dart';
import '../../shared/widgets/dribbble_background.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String? initialOtp;

  const OtpScreen({super.key, required this.phone, this.initialOtp});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  late final List<TextEditingController> _controllers =
      List.generate(AppConfig.otpLength, (index) {
    final controller = TextEditingController();
    if (widget.initialOtp != null && index < widget.initialOtp!.length) {
      controller.text = widget.initialOtp![index];
    }
    return controller;
  });

  int _resendTimer = AppConfig.otpResendSeconds;
  Timer? _timer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimer > 0) {
        setState(() => _resendTimer--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _controllers.map((c) => c.text).join();
    if (otp.length < AppConfig.otpLength || _isVerifying) return;

    setState(() => _isVerifying = true);

    try {
      // 1. Verify OTP with Gixbee API
      await ref.read(authRepositoryProvider).verifyOtp(
            phoneNumber: widget.phone,
            token: otp,
          );

      // 2. Register FCM token with the backend so NestJS can push to this device
      await _registerFcmToken();

      // 3. Navigate to main app
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainWrapper()),
          (route) => false,
        );
      }
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

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken =
          await ref.read(notificationServiceProvider).getDeviceToken();
      if (fcmToken != null) {
        await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
        debugPrint('[FCM] Token registered with backend');
      }
    } catch (e) {
      // Non-fatal — user can still use the app, just won't receive push notifications
      debugPrint('[FCM] Token registration failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: DribbbleBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  'Verification',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the ${AppConfig.otpLength}-digit code sent to\n${widget.phone}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                ),

                const SizedBox(height: 48),

                // OTP digit inputs
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(AppConfig.otpLength, (index) {
                    return Container(
                      width: 45,
                      height: 55,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _controllers[index].text.isNotEmpty
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white.withValues(alpha: 0.2),
                          width:
                              _controllers[index].text.isNotEmpty ? 1.5 : 1.0,
                        ),
                      ),
                      child: TextField(
                        controller: _controllers[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        cursorColor: Colors.white,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) {
                          setState(() {});
                          if (value.isNotEmpty &&
                              index < AppConfig.otpLength - 1) {
                            FocusScope.of(context).nextFocus();
                          }
                          if (index == AppConfig.otpLength - 1 &&
                              value.isNotEmpty) {
                            _verify();
                          }
                        },
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // Resend timer
                Center(
                  child: GestureDetector(
                    onTap: _resendTimer == 0
                        ? () async {
                            setState(
                                () => _resendTimer = AppConfig.otpResendSeconds);
                            _startTimer();
                            final newOtp = await ref
                                .read(authRepositoryProvider)
                                .signInWithPhone(widget.phone);
                            // Update the OTP fields with the new code
                            if (newOtp != null && mounted) {
                              setState(() {
                                for (int i = 0; i < _controllers.length; i++) {
                                  _controllers[i].text =
                                      i < newOtp.length ? newOtp[i] : '';
                                }
                              });
                            }
                          }
                        : null,
                    child: Text(
                      _resendTimer > 0
                          ? 'Resend code in ${_resendTimer}s'
                          : 'Resend Code',
                      style: TextStyle(
                        color: _resendTimer > 0
                            ? Colors.white.withValues(alpha: 0.5)
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                ElevatedButton(
                  onPressed: _isVerifying ? null : _verify,
                  child: _isVerifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
