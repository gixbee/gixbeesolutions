import 'package:flutter/material.dart';
import '../../theme.dart';

class DribbbleBackground extends StatelessWidget {
  final Widget child;

  const DribbbleBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final gx = context.gx;
    // These radial glows are a dark-mode mesh-gradient effect — on the Grab
    // light theme the same alphas read as muddy colour smears on a white
    // canvas, so we dial them down instead of removing them outright (the
    // light mockup still wants a faint accent tint).
    final isLight = context.gxIsLight;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: gx.bg,
            gradient: RadialGradient(
              center: const Alignment(-0.8, -0.8),
              radius: 1.2,
              colors: [
                gx.accent.withValues(alpha: isLight ? 0.06 : 0.15),
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
                gx.accentSoft.withValues(alpha: isLight ? 0.05 : 0.12),
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
                colorScheme.tertiary.withValues(alpha: isLight ? 0.04 : 0.1),
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
