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

/// Root screen for the "Find a Job" module.
/// Tabs: Jobs (board) · Offers (Smart Hiring) · Job Types · Applications (classic).
///
/// Smart Hiring loop: Job Types feed Hire Employee matching → Offers tab.
/// Classic board: Jobs apply → Applications tracker (separate pipeline).
class FindJobModule extends ConsumerStatefulWidget {
  /// Optional initial tab: 0 Jobs, 1 Offers, 2 Job Types, 3 Applications.
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
  /// Job Types (Smart Hiring) are nudged separately on Offers / Job Types tabs.
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

    final screens = [
      JobAlertsScreen(onOpenApplications: () => _goToTab(3)),
      HiringOffersScreen(onGoToJobTypes: () => _goToTab(2)),
      JobTypesScreen(onCreatedHint: () => _goToTab(1)),
      const ApplicationTrackerScreen(),
    ];

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: screens[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _goToTab,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: GixbeeTheme.accentGreen.withValues(alpha: 0.18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work, color: GixbeeTheme.accentGreen),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active,
                color: GixbeeTheme.accentGreen),
            label: 'Offers',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge, color: GixbeeTheme.accentGreen),
            label: 'Job Types',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon:
                Icon(Icons.assignment, color: GixbeeTheme.accentGreen),
            label: 'Apps',
          ),
        ],
      ),
    );
  }
}
