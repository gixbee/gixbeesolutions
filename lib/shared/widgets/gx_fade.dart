import 'package:flutter/material.dart';

/// Gixbee 2026 design language — content cross-fade.
///
/// A dependency-free thin wrapper over [AnimatedSwitcher] with the app's
/// standard fade, used to soften state/content swaps that would otherwise
/// hard-cut (loading→data, tab body changes). This completes design-language
/// item 8 ("AnimatedSwitcher for tab/content changes") for the gx_* family.
///
/// The [child] MUST carry a distinct [Key] per visual state for the switch to
/// fire — typically a `KeyedSubtree(key: ValueKey('loading'/'data'/...))`
/// wrapping the state-producing expression (e.g. an `AsyncValue.when`).
class GxFade extends StatelessWidget {
  const GxFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: child,
    );
  }
}
