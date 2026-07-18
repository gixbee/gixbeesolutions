import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme.dart';

/// Gixbee 2026 design language — branded glass toast.
///
/// Drop-in replacement for the stock Material [SnackBar] used app-wide. Renders
/// a floating dark-glass rounded pill (same translucent `#14141E` surface, thin
/// white border and `BackdropFilter` blur as [showGxSheet] / [showGxDialog]) with
/// a leading semantic accent icon, so transient feedback reads as part of the
/// v106 language instead of a flat Material bar. Dependency-free.
///
/// Semantics map to the app-wide palette decided in earlier passes:
/// success → green, error → red, info → violet (the main-app primary).
enum GxSnackType { success, error, info }

/// Builds a v106 glass [SnackBar] without showing it. Use this when you only
/// hold a captured [ScaffoldMessengerState] (e.g. after an `await`, where using
/// `context` would be unsafe): `messenger.showSnackBar(gxSnackBar('…'))`.
/// Most call sites should prefer [showGxSnack] instead.
SnackBar gxSnackBar(
  String message, {
  GxSnackType type = GxSnackType.info,
  Duration? duration,
}) {
  final Color accent;
  final IconData icon;
  switch (type) {
    case GxSnackType.success:
      accent = GixbeeTheme.accentGreen;
      icon = Icons.check_circle_rounded;
      break;
    case GxSnackType.error:
      accent = const Color(0xFFEF4444); // red-500, matches semantic error
      icon = Icons.error_rounded;
      break;
    case GxSnackType.info:
      accent = GixbeeTheme.accentPurple;
      icon = Icons.info_rounded;
      break;
  }

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    duration: duration ??
        (type == GxSnackType.error
            ? const Duration(seconds: 4)
            : const Duration(seconds: 3)),
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    content: _GxSnackBody(message: message, accent: accent, icon: icon),
  );
}

/// Shows a v106 glass toast. Mirrors `ScaffoldMessenger.showSnackBar` semantics
/// (queues, auto-dismisses) but with the branded surface. Pass [type] to pick
/// the accent + icon; [duration] defaults to 3s (4s for errors so they linger).
void showGxSnack(
  BuildContext context,
  String message, {
  GxSnackType type = GxSnackType.info,
  Duration? duration,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(gxSnackBar(message, type: type, duration: duration));
}

class _GxSnackBody extends StatelessWidget {
  final String message;
  final Color accent;
  final IconData icon;

  const _GxSnackBody({
    required this.message,
    required this.accent,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: context.gx.card.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.gx.ink.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: context.gx.ink.withValues(alpha: 0.92),
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
