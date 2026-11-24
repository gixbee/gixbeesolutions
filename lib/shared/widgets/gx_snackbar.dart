import 'dart:async';
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

OverlayEntry? _gxSnackEntry;

(Color accent, IconData icon) _snackChrome(GxSnackType type) {
  switch (type) {
    case GxSnackType.success:
      return (GixbeeTheme.accentGreen, Icons.check_circle_rounded);
    case GxSnackType.error:
      return (const Color(0xFFEF4444), Icons.error_rounded);
    case GxSnackType.info:
      return (GixbeeTheme.accentPurple, Icons.info_rounded);
  }
}

Duration _snackDuration(GxSnackType type, Duration? duration) =>
    duration ??
    (type == GxSnackType.error
        ? const Duration(seconds: 4)
        : const Duration(seconds: 3));

void _hideGxSnackOverlay() {
  final entry = _gxSnackEntry;
  _gxSnackEntry = null;
  if (entry == null) return;
  if (entry.mounted) entry.remove();
}

/// Builds a v106 glass [SnackBar] without showing it. Use this when you only
/// hold a captured [ScaffoldMessengerState] (e.g. after an `await`, where using
/// `context` would be unsafe): `messenger.showSnackBar(gxSnackBar('…'))`.
/// Most call sites should prefer [showGxSnack] instead.
SnackBar gxSnackBar(
  String message, {
  GxSnackType type = GxSnackType.info,
  Duration? duration,
}) {
  final (accent, icon) = _snackChrome(type);
  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.transparent,
    elevation: 0,
    duration: _snackDuration(type, duration),
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    content: _GxSnackBody(message: message, accent: accent, icon: icon),
  );
}

/// Shows a v106 glass toast. Drawn on the root [Overlay] so it stays visible
/// above modal sheets (address form, rental editor) instead of painting on
/// the Scaffold behind them. Falls back to [ScaffoldMessenger] when no overlay
/// is available. Pass [type] for accent + icon; [duration] defaults to 3s
/// (4s for errors).
void showGxSnack(
  BuildContext context,
  String message, {
  GxSnackType type = GxSnackType.info,
  Duration? duration,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(gxSnackBar(message, type: type, duration: duration));
    return;
  }
  _hideGxSnackOverlay();
  final (accent, icon) = _snackChrome(type);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom +
          MediaQuery.paddingOf(ctx).bottom +
          14;
      return Positioned(
        left: 14,
        right: 14,
        bottom: bottom,
        child: _GxSnackLifetime(
          duration: _snackDuration(type, duration),
          onTimeout: _hideGxSnackOverlay,
          child: Material(
            color: Colors.transparent,
            child: _GxSnackBody(message: message, accent: accent, icon: icon),
          ),
        ),
      );
    },
  );
  _gxSnackEntry = entry;
  overlay.insert(entry);
}

class _GxSnackLifetime extends StatefulWidget {
  final Duration duration;
  final VoidCallback onTimeout;
  final Widget child;

  const _GxSnackLifetime({
    required this.duration,
    required this.onTimeout,
    required this.child,
  });

  @override
  State<_GxSnackLifetime> createState() => _GxSnackLifetimeState();
}

class _GxSnackLifetimeState extends State<_GxSnackLifetime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, widget.onTimeout);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
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
