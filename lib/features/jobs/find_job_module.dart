import 'package:flutter/material.dart';
import 'job_alerts_screen.dart';
import 'hiring_offers_screen.dart';
import 'job_types_screen.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../theme.dart';

/// Root screen for the "Find a Job" module.
/// Tabs: Jobs (board) · Offers (Smart Hiring) · Job Types (preferences).
class FindJobModule extends StatefulWidget {
  /// Optional initial tab: 0 Jobs, 1 Offers, 2 Job Types.
  final int initialIndex;

  const FindJobModule({super.key, this.initialIndex = 0});

  @override
  State<FindJobModule> createState() => _FindJobModuleState();
}

class _FindJobModuleState extends State<FindJobModule> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 2);
  }

  final _screens = const [
    JobAlertsScreen(),
    HiringOffersScreen(),
    JobTypesScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: _screens[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
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
        ],
      ),
    );
  }
}
