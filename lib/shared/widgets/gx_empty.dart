import 'package:flutter/material.dart';
import '../../theme.dart';
import 'gx_pressable.dart';

/// Gixbee 2026 design language — branded empty / zero-result state.
///
/// Replaces the ad-hoc `Center(Text(...))` strings and grey icon columns
/// that list screens used to show when there is nothing to display, with
/// ONE consistent v106 surface: an accent-tinted squircle icon tile, a
/// strong title, a muted subtitle, and an optional CTA pill.
///
/// Dependency-free. Pass the screen's quad [accent] (e.g. accentViolet for
/// Messages, accentBlue for Business) so the empty state matches its section;
/// defaults to the shared main-app `accentPurple`.
class GxEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Color? accent;
  final List<Color>? accentGradient;
  final String? actionLabel;
  final VoidCallback? onAction;

  const GxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.accent,
    this.accentGradient,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final Color acc = accent ?? context.gx.accent;
    final gradient = accentGradient ?? context.gx.accentGradient;
    final hasAction = actionLabel != null && onAction != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: acc.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: acc.withValues(alpha: 0.30)),
              ),
              child: Icon(icon, size: 38, color: acc),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.gx.ink,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: context.gx.ink.withValues(alpha: 0.55),
                ),
              ),
            ],
            if (hasAction) ...[
              const SizedBox(height: 22),
              GxPressable(
                onTap: onAction,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    actionLabel!,
                    style: TextStyle(
                      color: context.gx.onAccent, // sits on the accent gradient
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
