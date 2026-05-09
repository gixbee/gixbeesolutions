import 'package:flutter/material.dart';

/// A polished, reusable "Coming Soon" placeholder screen.
/// Use for features that are planned but not yet implemented.
class ComingSoonScreen extends StatelessWidget {
  final String featureName;
  final IconData icon;

  const ComingSoonScreen({
    super.key,
    required this.featureName,
    this.icon = Icons.rocket_launch_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(featureName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon container
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) => Transform.scale(
                  scale: value,
                  child: child,
                ),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        cs.primary.withValues(alpha: 0.15),
                        cs.tertiary.withValues(alpha: 0.1),
                      ],
                    ),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 52,
                    color: cs.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                '$featureName is\nComing Soon!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'We\'re working hard to bring this feature to you. '
                'Stay tuned for updates!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 36),

              // Back button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
