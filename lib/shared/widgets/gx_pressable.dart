import 'package:flutter/material.dart';

/// Gixbee 2026 design language — scale-on-press feedback wrapper.
/// Wrap any card/CTA to get the subtle "push" micro-interaction used by
/// Grab/Gojek-style super-apps. Dependency-free.
class GxPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const GxPressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.965,
  });

  @override
  State<GxPressable> createState() => _GxPressableState();
}

class _GxPressableState extends State<GxPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
