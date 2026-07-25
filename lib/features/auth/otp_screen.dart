import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/config/app_config.dart';
import '../../main_wrapper.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'auth_chrome.dart';
import 'registration_screen.dart';
import '../../repositories/auth_repository.dart';
import '../../services/notification_service.dart';

/// OTP verification — restyled to the orange super-app mockup:
/// dark radial backdrop, branded digit boxes, demo helper banner,
/// brand-gradient Verify CTA. Logic (verify → FCM → profile route) unchanged.
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
      // 1. Verify OTP with Gixbee backend
      await ref.read(authRepositoryProvider).verifyOtp(
            phoneNumber: widget.phone,
            token: otp,
          );

      // 2. Register FCM token — gives the backend a device to push to
      await _registerFcmToken();

      // 3. Check profile to decide where to navigate
      final user = await ref.read(authRepositoryProvider).getProfile();
      final isNewUser = user == null || (user.name?.isEmpty ?? true);

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) =>
              isNewUser ? const RegistrationScreen() : const MainWrapper(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Verification failed: $e',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  /// Register the FCM device token with the backend immediately after login.
  /// This ensures NestJS can push job request notifications to this device.
  ///
  /// NOTE: We do NOT call notificationService.initialize() here.
  ///   - initialize() is called ONCE in main_wrapper._initNotifications()
  ///     after this screen navigates away and MainWrapper mounts.
  ///   - Calling initialize() here would register the background handler
  ///     and local notification plugin a second time before MainWrapper
  ///     has even mounted, causing duplicate listeners.
  ///   - getDeviceToken() works without initialize() because Firebase is
  ///     already initialized in main() via Firebase.initializeApp().
  Future<void> _registerFcmToken() async {
    try {
      final fcmToken =
          await ref.read(notificationServiceProvider).getDeviceToken();
      if (fcmToken != null) {
        await ref.read(authRepositoryProvider).registerFcmToken(fcmToken);
        debugPrint('[FCM] Token registered with backend after OTP login');
      }
    } catch (e) {
      // Non-fatal — user can use the app, just won't receive push notifications
      debugPrint('[FCM] Token registration failed (non-fatal): $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GixbeeTheme.background,
      body: AuthBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthBackButton(),
                const SizedBox(height: 28),
                Text(
                  'Enter code',
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a ${AppConfig.otpLength}-digit code to ${widget.phone}',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 36),

                // OTP digit inputs
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(AppConfig.otpLength, (index) {
                    final filled = _controllers[index].text.isNotEmpty;
                    return Container(
                      width: 45,
                      height: 55,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A26),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: filled
                              ? GixbeeTheme.brandOrange
                              : const Color(0xFF2A2A3A),
                          width: filled ? 1.5 : 1.0,
                        ),
                      ),
                      child: TextField(
                        controller: _controllers[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        cursorColor: GixbeeTheme.brandOrange,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 12),
                        ),
                        onChanged: (value) {
                          setState(() {});
                          if (value.isNotEmpty &&
                              index < AppConfig.otpLength - 1) {
                            FocusScope.of(context).nextFocus();
                          } else if (value.isEmpty && index > 0) {
                            FocusScope.of(context).previousFocus();
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

                Center(
                  child: GestureDetector(
                    onTap: _resendTimer == 0
                        ? () async {
                            try {
                              final newOtp = await ref
                                  .read(authRepositoryProvider)
                                  .signInWithPhone(widget.phone);

                              if (!mounted) return;
                              setState(() {
                                _resendTimer = AppConfig.otpResendSeconds;
                              });
                              _startTimer();

                              if (kDebugMode && newOtp != null && mounted) {
                                setState(() {
                                  for (int i = 0;
                                      i < _controllers.length;
                                      i++) {
                                    _controllers[i].text =
                                        i < newOtp.length ? newOtp[i] : '';
                                  }
                                });
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              showGxSnack(context, 'Resend failed. Try again.',
                                  type: GxSnackType.error);
                            }
                          }
                        : null,
                    child: Text(
                      _resendTimer > 0
                          ? 'Resend code in ${_resendTimer}s'
                          : 'Resend code',
                      style: GoogleFonts.outfit(
                        color: _resendTimer > 0
                            ? Colors.white.withValues(alpha: 0.45)
                            : GixbeeTheme.brandOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                if (kDebugMode && widget.initialOtp != null) ...[
                  _devBanner(),
                  const SizedBox(height: 12),
                ],

                AuthPrimaryButton(
                  label: 'Verify',
                  loading: _isVerifying,
                  onPressed: _verify,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _devBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GixbeeTheme.brandOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: GixbeeTheme.brandOrange.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        'Debug — code ${widget.initialOtp} is prefilled.',
        style: GoogleFonts.outfit(
          color: GixbeeTheme.brandOrange,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
