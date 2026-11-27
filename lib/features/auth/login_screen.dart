import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/utils/api_error_message.dart';

import '../../core/config/app_config.dart';
import '../../repositories/auth_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'auth_chrome.dart';
import 'otp_screen.dart';

/// Phone sign-in — grab-green auth look (theme-aware via AuthPalette):
/// brand wordmark, clear title, single phone card with +91 chip, trust row,
/// and the green CTA pinned above the keyboard-safe footer.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _enter;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    var phone = _phoneController.text.trim().replaceAll(RegExp(r'\s+'), '');
    if (!phone.startsWith('+')) {
      phone = '${AppConfig.defaultCountryCode}$phone';
    }
    if (phone.length < AppConfig.phoneMinLength) {
      showGxSnack(context, 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() => _isSending = true);
    try {
      final devOtp =
          await ref.read(authRepositoryProvider).signInWithPhone(phone);
      if (!mounted) return;

      if (devOtp != null) {
        showGxSnack(
          context,
          'Dev OTP: $devOtp',
          type: GxSnackType.success,
          duration: const Duration(seconds: 6),
        );
      }

      Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (_, __, ___) => OtpScreen(
            phone: phone,
            initialOtp: devOtp,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showGxSnack(
          context,
          apiErrorMessage(e, fallback: 'Could not send code. Try again.'),
          type: GxSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    return Scaffold(
      backgroundColor: p.bgBottom,
      resizeToAvoidBottomInset: true,
      body: AuthBackdrop(
        child: SafeArea(
          child: AuthEntrance(
            animation: _enter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthBackButton(),
                  const SizedBox(height: 28),
                  const AuthWordmark(fontSize: 38),
                  const SizedBox(height: 26),
                  Text(
                    'Sign in with mobile',
                    style: GoogleFonts.outfit(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\u2019ll text you a one-time code — no passwords. '
                    'New numbers are registered automatically.',
                    style: GoogleFonts.outfit(
                      fontSize: 14.5,
                      height: 1.45,
                      color: p.sub,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _phoneField(p),
                  const SizedBox(height: 14),
                  _trustRow(p),
                  if (kDebugMode) ...[
                    const SizedBox(height: 14),
                    _devBanner(),
                  ],
                  const Spacer(),
                  AuthPrimaryButton(
                    label: 'Send code',
                    loading: _isSending,
                    onPressed: _sendCode,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Standard SMS rates may apply.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: p.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneField(AuthPalette p) {
    final focused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused ? kAuthGreen : p.surfaceBorder,
          width: focused ? 1.6 : 1,
        ),
        boxShadow: [
          if (p.isLight)
            BoxShadow(
              color: focused
                  ? kAuthGreen.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: focused ? 16 : 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          // Country chip
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: kAuthGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '\u{1F1EE}\u{1F1F3}  ${AppConfig.defaultCountryCode}',
              style: GoogleFonts.outfit(
                color: kAuthGreenDeep,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _phoneController,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _sendCode(),
              style: GoogleFonts.outfit(
                color: p.ink,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
              decoration: InputDecoration(
                hintText: '98765 43210',
                counterText: '',
                hintStyle: GoogleFonts.outfit(
                  color: p.faint,
                  letterSpacing: 0.8,
                ),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trustRow(AuthPalette p) {
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: p.faint),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Your number is used only for login and job contact.',
            style: GoogleFonts.outfit(fontSize: 12, color: p.faint),
          ),
        ),
      ],
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
      child: Row(
        children: [
          const Icon(Icons.bug_report_outlined,
              size: 16, color: kAuthGreenDeep),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Debug build — OTP may be echoed when ALLOW_OTP_ECHO is on.',
              style: GoogleFonts.outfit(
                color: kAuthGreenDeep,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
