import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/matching_repository.dart';
import '../../repositories/talent_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../theme.dart';
import 'application_tracker_screen.dart';
import 'hiring_offers_screen.dart';
import 'job_alerts_screen.dart';
import 'job_types_screen.dart';
import 'seeker_profile_wizard.dart';

/// Root screen for Find a Job.
/// Tabs: Jobs · Invites · Profile · Applications.
class FindJobModule extends ConsumerStatefulWidget {
  /// Optional initial tab: 0 Jobs, 1 Invites, 2 Profile, 3 Applications.
  final int initialIndex;

  const FindJobModule({super.key, this.initialIndex = 0});

  @override
  ConsumerState<FindJobModule> createState() => _FindJobModuleState();
}

class _FindJobModuleState extends ConsumerState<FindJobModule> {
  late int _currentIndex;
  bool _gateChecked = false;
  int _jobsReload = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenSeekerGate());
  }

  /// Opens the job profile wizard when the seeker profile is missing or incomplete.
  Future<void> _maybeOpenSeekerGate() async {
    if (_gateChecked || !mounted) return;
    _gateChecked = true;
    try {
      final profiles =
          await ref.read(matchingRepositoryProvider).listPreferences();
      if (!mounted) return;
      final profile = await ref.read(talentRepositoryProvider).getProfile();
      if (!mounted || (profiles.isNotEmpty && !jobProfileNeedsWizard(profile))) {
        return;
      }
      await _openWizard(
        existing: profiles.isEmpty
            ? null
            : {
                ...profiles.first,
                'availableOn': profile['availableOn'],
              },
      );
    } catch (_) {
      // Soft-fail — user can still open the tabs.
    }
  }

  Future<void> _openWizard({Map<String, dynamic>? existing}) async {
    var profile = existing;
    while (mounted) {
      final result = await Navigator.push<SeekerProfileResult>(
        context,
        MaterialPageRoute(
            builder: (_) => SeekerProfileWizard(existing: profile)),
      );
      if (!mounted || result == null) return;
      setState(() {
        _jobsReload++;
        _currentIndex = 2;
      });
      if (result != SeekerProfileResult.createAnother) return;
      profile = null;
    }
  }

  void _goToTab(int i) {
    if (!mounted) return;
    setState(() => _currentIndex = i.clamp(0, 3));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = context.gx.accent;

    final screens = [
      JobAlertsScreen(
        reloadToken: _jobsReload,
        onOpenApplications: () => _goToTab(3),
        onCreateProfile: () => _openWizard(),
        onEditProfile: () => _goToTab(2),
      ),
      HiringOffersScreen(onGoToProfiles: () => _goToTab(2)),
      JobTypesScreen(
        onCreatedHint: () => _goToTab(0),
      ),
      const ApplicationTrackerScreen(),
    ];

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: screens[_currentIndex],
      ),
      bottomNavigationBar: Semantics(
        label: 'Find a Job navigation',
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _goToTab,
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          indicatorColor: accent.withValues(alpha: 0.18),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.work_outline),
              selectedIcon: Icon(Icons.work, color: accent),
              label: 'Jobs',
            ),
            NavigationDestination(
              icon: const Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications, color: accent),
              label: 'Invites',
            ),
            NavigationDestination(
              icon: const Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge, color: accent),
              label: 'Profile',
            ),
            NavigationDestination(
              icon: const Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment, color: accent),
              label: 'Applications',
            ),
          ],
        ),
      ),
    );
  }
}
