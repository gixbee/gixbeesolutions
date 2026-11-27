import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main_wrapper.dart';
import '../../repositories/auth_repository.dart';
import '../onboarding/welcome_screen.dart';
import 'registration_screen.dart';

class SignedInGate extends ConsumerStatefulWidget {
  const SignedInGate({super.key});

  @override
  ConsumerState<SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends ConsumerState<SignedInGate> {
  bool _admitted = false;

  @override
  Widget build(BuildContext context) {
    if (_admitted) return const MainWrapper();
    return ref.watch(currentUserProvider).when(
      skipLoadingOnRefresh: false,
          data: (user) {
            if (user == null) return const WelcomeScreen();
            if (user.profileSetupRequired) return const RegistrationScreen();
        _admitted = true;
            return const MainWrapper();
          },
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your profile.'),
                  FilledButton(
                    onPressed: () => ref.invalidate(currentUserProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        );
  }
}
