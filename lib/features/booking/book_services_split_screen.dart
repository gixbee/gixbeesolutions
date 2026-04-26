import 'package:flutter/material.dart';
import '../search/worker_list_screen.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/glass_container.dart';

/// Split screen shown when user taps "Book Services" on home.
/// Two clear intents: plan ahead or get help now.
class BookServicesSplitScreen extends StatelessWidget {
  const BookServicesSplitScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: DribbbleBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // ── TOP BAR ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_ios, color: colorScheme.onSurface, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      'Book Services',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── QUESTION ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'How urgently do you\nneed help?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select a booking method to proceed',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 48),

              // ── TWO CARDS ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // ━━━ CARD 1: INSTANT HELP ━━━
                    _ModernSplitCard(
                      icon: Icons.bolt_rounded,
                      accentColor: const Color(0xFFFF6B6B),
                      title: 'Instant Help',
                      subtitle: 'Emergency? Get a pro in minutes',
                      tagLabel: 'FASTEST',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WorkerListScreen(category: null, isInstant: true),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // ━━━ CARD 2: PLAN SERVICES ━━━
                    _ModernSplitCard(
                      icon: Icons.calendar_month_rounded,
                      accentColor: const Color(0xFF6C63FF),
                      title: 'Plan Ahead',
                      subtitle: 'Schedule for a later date & time',
                      tagLabel: 'RECOMMENDED',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WorkerListScreen(category: null, isInstant: false),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // ── BOTTOM HINT ──
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
                child: Center(
                  child: GlassContainer(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_user_rounded, size: 16, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'Secure payments & verified pros',
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModernSplitCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final String tagLabel;
  final VoidCallback onTap;

  const _ModernSplitCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.tagLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tagLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 36),
            ),
          ],
        ),
      ),
    );
  }
}

