import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/talent_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../theme.dart';
import 'application_tracker_screen.dart';
import 'hiring_offers_screen.dart';
import 'job_alerts_screen.dart';
import 'job_types_screen.dart';
import 'seeker_profile_wizard.dart';

/// Root screen for the "Find a Job" module (v147 IA).
/// Tabs: Board (classic) · Alerts (Smart Hiring) · Profiles · Apps.
///
/// Smart Hiring loop: Profiles feed Hire Employee matching → Alerts tab.
/// Classic board: Board apply → Apps tracker (separate pipeline).
class FindJobModule extends ConsumerStatefulWidget {
  /// Optional initial tab: 0 Board, 1 Alerts, 2 Profiles, 3 Apps.
  final int initialIndex;

  const FindJobModule({super.key, this.initialIndex = 0});

  @override
  ConsumerState<FindJobModule> createState() => _FindJobModuleState();
}

class _FindJobModuleState extends ConsumerState<FindJobModule> {
  late int _currentIndex;
  bool _gateChecked = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenSeekerGate());
  }

  /// First-run gate: incomplete TalentProfile → classic seeker wizard.
  /// Profiles (Smart Hiring) are nudged separately on Alerts / Profiles tabs.
  Future<void> _maybeOpenSeekerGate() async {
    if (_gateChecked || !mounted) return;
    _gateChecked = true;
    try {
      final p = await ref.read(talentRepositoryProvider).getProfile();
      final roles = (p['preferredRoles'] as List? ?? []);
      final salary = p['expectedSalary'];
      final incomplete = roles.isEmpty && salary == null;
      if (!incomplete || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => const SeekerProfileWizard()),
      );
    } catch (_) {
      // Soft-fail — user can still browse tabs.
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
      JobAlertsScreen(onOpenApplications: () => _goToTab(3)),
      HiringOffersScreen(onGoToProfiles: () => _goToTab(2)),
      JobTypesScreen(onCreatedHint: () => _goToTab(1)),
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
              icon: const Icon(Icons.view_list_outlined),
              selectedIcon: Icon(Icons.view_list, color: accent),
              label: 'Board',
            ),
            NavigationDestination(
              icon: const Icon(Icons.notifications_active_outlined),
              selectedIcon: Icon(Icons.notifications_active, color: accent),
              label: 'Alerts',
            ),
            NavigationDestination(
              icon: const Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge, color: accent),
              label: 'Profiles',
            ),
            NavigationDestination(
              icon: const Icon(Icons.assignment_outlined),
              selectedIcon: Icon(Icons.assignment, color: accent),
              label: 'Apps',
            ),
          ],
        ),
      ),
    );
  }
}
