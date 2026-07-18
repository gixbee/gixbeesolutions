import 'package:flutter/material.dart';
import '../../theme.dart';

/// Gixbee 2026 design language — pulsing skeleton placeholder.
/// Hand-rolled (no shimmer package): a rounded block whose opacity
/// breathes while content loads. Compose into rows/strips per screen.
class GxSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const GxSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = 14,
  });

  @override
  State<GxSkeleton> createState() => _GxSkeletonState();
}

class _GxSkeletonState extends State<GxSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.75).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: context.gx.card2,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: context.gx.border),
        ),
      ),
    );
  }
}

/// Horizontal strip of skeleton cards — drop-in for loading list strips.
class GxSkeletonStrip extends StatelessWidget {
  final double cardWidth;
  final double cardHeight;
  final int count;

  const GxSkeletonStrip({
    super.key,
    required this.cardWidth,
    required this.cardHeight,
    this.count = 3,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (_, __) =>
          GxSkeleton(width: cardWidth, height: cardHeight),
    );
  }
}
