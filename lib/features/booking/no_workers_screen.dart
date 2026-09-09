import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import 'instant_help_screen.dart';
import 'instant_request_screen.dart';

/// Instant Help fallback when no worker accepts in time (v126 mockup c21).
/// Replaces the old bare "Request Status" dialog: explains what happened and
/// offers real next steps — retry with another worker for the same skill,
/// switch service, or go home. (v126 also shows "Notify me when available";
/// deliberately NOT included until a real notify backend exists — we never
/// fake a success.)
class NoWorkersScreen extends StatelessWidget {
  final String skill;

  const NoWorkersScreen({super.key, required this.skill});

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: context.gx.accentSoft.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.search_off_rounded,
                      color: context.gx.accentSoft, size: 40),
                ),
                const SizedBox(height: 24),
                Text(
                  'No pros available right now',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nobody could take your $skill request in time. '
                  'No service charge is due. You can try again or choose another service.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: context.gx.ink.withValues(alpha: 0.6)),
                ),
                const Spacer(),
                GxButton(
                  label: 'Try again now',
                  onTap: () {
                    // Re-open the request for the same service — the next
                    // broadcast may find pros who just went live.
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => InstantRequestScreen(skill: skill),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                GxPressable(
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InstantHelpScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.gx.border, width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Try a different service',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => _goHome(context),
                  child: Text(
                    'Back to home',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.gx.ink.withValues(alpha: 0.55)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
