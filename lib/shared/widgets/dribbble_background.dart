import 'package:flutter/material.dart';
import '../../theme.dart';

/// Soft page chrome. Light mode stays nearly flat (readable headers); dark
/// mode keeps a subtle accent mesh.
class DribbbleBackground extends StatelessWidget {
  final Widget child;

  const DribbbleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final isLight = context.gxIsLight;

    // Light / Grab: flat scaffold tint only — radial greens were painting a
    // near-black forest blotch behind dark ink titles (Find Job, Messages).
    if (isLight) {
      return ColoredBox(
        color: gx.bg,
        child: child,
      );
    }

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: gx.bg,
            gradient: RadialGradient(
              center: const Alignment(-0.8, -0.8),
              radius: 1.2,
              colors: [
                gx.accent.withValues(alpha: 0.15),
                gx.bg,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.8, -0.5),
              radius: 1.0,
              colors: [
                gx.accentSoft.withValues(alpha: 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.0, 1.2),
              radius: 1.5,
              colors: [
                Theme.of(context)
                    .colorScheme
                    .tertiary
                    .withValues(alpha: 0.1),
                Colors.transparent,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
