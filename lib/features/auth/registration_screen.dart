import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/profile_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'auth_chrome.dart';

/// Fresh-user profile setup — name only.
///
/// Gixbee is intent-based: a single account can book, go live, hire, or list a
/// business later from Home. No Customer/Worker choice at signup.
/// Theme matches Login/OTP via [AuthPalette] (Grab green, light/dark aware).
/// Name is required so bookings, chat, and ratings show a real display name.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _enter;
  bool _isSubmitting = false;

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
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showGxSnack(context, 'Please enter your name');
      return;
    }
    if (name.length < 2) {
      showGxSnack(context, 'Enter a name with at least 2 characters');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      var user = await ref.read(currentUserProvider.future);
      if (user == null) {
        ref.invalidate(currentUserProvider);
        user = await ref.read(authRepositoryProvider).getProfile();
      }
      if (user == null) {
        throw Exception(
          'User session not found. Please try logging in again.',
        );
      }

      // Name only — keep the CUSTOMER role from OTP signup. Worker /
      // business / talent intents are opted into later from Home.
      await ref.read(profileRepositoryProvider).updateProfile(
        userId: user.id,
        data: {'name': name},
      );
      ref.invalidate(currentUserProvider);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainWrapper()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        showGxSnack(
          context,
          'Failed to update profile: $e',
          type: GxSnackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    final focused = _focusNode.hasFocus;

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
                  const SizedBox(height: 28),
                  const AuthWordmark(fontSize: 38),
                  const SizedBox(height: 26),
                  Text(
                    'Welcome to Gixbee!',
                    style: GoogleFonts.outfit(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: p.ink,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'What should we call you? You can book, work, hire, or '
                    'list a business anytime from Home — no role to pick now.',
                    style: GoogleFonts.outfit(
                      fontSize: 14.5,
                      height: 1.45,
                      color: p.sub,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: focused ? kAuthGreen : p.surfaceBorder,
                        width: focused ? 1.6 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your name',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.sub,
                            letterSpacing: 0.2,
                          ),
                        ),
                        TextField(
                          controller: _nameController,
                          focusNode: _focusNode,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.name],
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: p.ink,
                          ),
                          decoration: InputDecoration(
                            hintText: 'e.g. Priya Sharma',
                            hintStyle: GoogleFonts.outfit(
                              color: p.faint,
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.only(top: 6, bottom: 10),
                          ),
                          onSubmitted: (_) => _continue(),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  AuthPrimaryButton(
                    label: 'Continue',
                    loading: _isSubmitting,
                    onPressed: _continue,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
