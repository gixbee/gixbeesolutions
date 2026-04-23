import 'package:flutter/material.dart';
import 'talent_profile_screen.dart';
import 'job_alerts_screen.dart';
import 'application_tracker_screen.dart';
import '../../shared/widgets/dribbble_background.dart';

/// Root screen for the "Find a Job" module.
/// Bottom nav with 3 tabs: Job Alerts, Applications, My Profile.
class FindJobModule extends StatefulWidget {
  const FindJobModule({super.key});

  @override
  State<FindJobModule> createState() => _FindJobModuleState();
}

class _FindJobModuleState extends State<FindJobModule> {
  int _currentIndex = 0;

  final _screens = const [
    JobAlertsScreen(),
    ApplicationTrackerScreen(),
    TalentProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DribbbleBackground(
        child: _screens[_currentIndex],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: cs.surface.withValues(alpha: 0.8), // Semi-transparent for M3 look
        indicatorColor: cs.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: 'Jobs',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Applications',
          ),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Talent Bio',
          ),
        ],
      ),
    );
  }
}

