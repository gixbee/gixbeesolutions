import 'package:flutter/material.dart';
import '../../theme.dart';
import 'gx_pressable.dart';

/// Gixbee 2026 design language — the shared pill button.
///
/// Stops every screen from hand-rolling a [GxPressable] + gradient/outline
/// `Container` pill. Two variants:
///   • filled  → a [gradient] fill (default = theme shell [GxColors.accentGradient])
///   • outline → transparent with an [accent]-tinted border + [accent] label
///
/// Per-screen quad colours are supported via [gradient] (filled) and [accent]
/// (outline + filled-disabled fallback) — e.g. business screens pass the
/// accentBlue pair. Null [gradient]/[accent] resolve from `context.gx` so
/// Gixbee Dark → violet and Grab Green → green automatically.
///
/// [loading] shows a small spinner and makes the button non-tappable.
/// A null [onTap] (with [loading] false) renders a dimmed, disabled pill.
class GxButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  /// true = gradient/solid fill, false = outline.
  final bool filled;

  /// Gradient for the filled variant. Null → [GxColors.accentGradient].
  final List<Color>? gradient;

  /// Accent colour for the outline variant (border + foreground).
  /// Null → [GxColors.accent].
  final Color? accent;

  final bool loading;
  final bool expand;
  final double height;
  final double radius;
  final double fontSize;

  const GxButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = true,
    this.gradient,
    this.accent,
    this.loading = false,
    this.expand = true,
    this.height = 54,
    this.radius = 14,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null && !loading;
    final List<Color> fill = gradient ?? context.gx.accentGradient;
    final Color acc = accent ?? context.gx.accent;

    // Filled fg sits on the gradient/solid fill — stays white in both themes.
    final Color fg = filled ? context.gx.onAccent : acc;

    final Widget content = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          );

    final Widget pill = Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        height: height,
        width: expand ? double.infinity : null,
        alignment: Alignment.center,
        padding: expand ? null : const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: filled
              ? LinearGradient(
                  colors: fill,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: filled ? null : context.gx.ink.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(radius),
          border: filled
              ? null
              : Border.all(color: acc.withValues(alpha: 0.5)),
        ),
        child: content,
      ),
    );

    return GxPressable(
      onTap: enabled ? onTap : null,
      child: pill,
    );
  }
}
