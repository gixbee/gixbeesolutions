import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/config/app_config.dart';
import '../../main_wrapper.dart';
import '../../shared/utils/api_error_message.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'auth_chrome.dart';
import 'registration_screen.dart';
import '../../repositories/auth_repository.dart';
import '../../services/notification_service.dart';
import '../../shared/models/user.dart';

/// OTP verification — grab-green auth look (theme-aware via AuthPalette):
/// branded digit boxes with green fill state, green resend link, green
/// Verify CTA. Logic (verify → FCM → profile route) unchanged.
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

      ref.invalidate(authStateProvider);
      final authed = await ref.read(authStateProvider.future);
      if (!authed) {
        throw Exception('Login did not persist. Try again.');
      }

      await _registerFcmToken();

      ref.invalidate(currentUserProvider);
      User? user;
      try {
        user = await ref.read(currentUserProvider.future);
      } catch (_) {
        user = await ref.read(authRepositoryProvider).getProfile();
      }
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
        showGxSnack(
          context,
          apiErrorMessage(
            e,
            fallback: 'Verification failed. Check the code and try again.',
          ),
          type: GxSnackType.error,
        );
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
    final p = AuthPalette.of(context);
    return Scaffold(
      backgroundColor: p.bgBottom,
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
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a ${AppConfig.otpLength}-digit code to ${widget.phone}',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    height: 1.4,
                    color: p.sub,
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
                        color: filled && p.isLight
                            ? kAuthGreen.withValues(alpha: 0.06)
                            : p.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: filled ? kAuthGreen : p.surfaceBorder,
                          width: filled ? 1.6 : 1.0,
                        ),
                        boxShadow: p.isLight
                            ? [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: TextField(
                        controller: _controllers[index],
                        textAlign: TextAlign.center,
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        cursorColor: kAuthGreen,
                        style: GoogleFonts.outfit(
                          color: p.ink,
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
                              showGxSnack(
                                context,
                                apiErrorMessage(
                                  e,
                                  fallback: 'Resend failed. Try again.',
                                ),
                                type: GxSnackType.error,
                              );
                            }
                          }
                        : null,
                    child: Text(
                      _resendTimer > 0
                          ? 'Resend code in ${_resendTimer}s'
                          : 'Resend code',
                      style: GoogleFonts.outfit(
                        color: _resendTimer > 0 ? p.faint : kAuthGreenDeep,
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
        color: kAuthGreen.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kAuthGreen.withValues(alpha: 0.28)),
      ),
      child: Text(
        'Debug — code ${widget.initialOtp} is prefilled.',
        style: GoogleFonts.outfit(
          color: kAuthGreenDeep,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
