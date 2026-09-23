import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme.dart';

/// Gixbee 2026 design language — glass surface for FLOATING layers only
/// (bottom sheets, overlay pills, summary cards). Subtle translucency +
/// thin border + optional backdrop blur. Never use as a full-screen bg.
class GxGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  const GxGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.blur = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: const SizedBox.expand(),
            ),
          ),
          Container(
            padding: padding,
            decoration: BoxDecoration(
              color: context.gx.card.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: context.gx.ink.withValues(alpha: 0.12)),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}
