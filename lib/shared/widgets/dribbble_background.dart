import 'package:flutter/material.dart';

class DribbbleBackground extends StatelessWidget {
  final Widget child;

  const DribbbleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // --- DRIBBBLE MESH GRADIENT BACKGROUND ---
        // Instead of heavy blurs, we use RadialGradients which are much more performant
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            gradient: RadialGradient(
              center: const Alignment(-0.8, -0.8),
              radius: 1.2,
              colors: [
                colorScheme.primary.withValues(alpha: 0.15),
                colorScheme.surface,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        
        // Second layer for the secondary glow
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, -0.5),
              radius: 1.0,
              colors: [
                colorScheme.secondary.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // Third layer for the bottom glow
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, 1.2),
              radius: 1.5,
              colors: [
                colorScheme.tertiary.withValues(alpha: 0.1),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),

        // --- ACTUAL CONTENT ---
        child,
      ],
    );
  }
}
