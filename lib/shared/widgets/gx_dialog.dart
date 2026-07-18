import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'gx_pressable.dart';

/// Gixbee 2026 design language — branded glass center dialog.
///
/// Drop-in replacement for Material's [AlertDialog] for simple
/// title / message / action confirmations. Matches the glass surface used by
/// [showGxSheet] (dark translucent card, thin white border, blurred backdrop)
/// so confirmations read as part of the v106 language instead of a stock
/// Material popup. Dependency-free.
///
/// Actions render as v106 pills: the [GxDialogAction.isPrimary] one gets the
/// [accentGradient] fill, the rest a soft translucent outline.
class GxDialogAction {
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;

  const GxDialogAction(
    this.label, {
    this.onTap,
    this.isPrimary = false,
  });
}

Future<T?> showGxDialog<T>(
  BuildContext context, {
  String? title,
  String? message,
  Widget? content,
  List<GxDialogAction> actions = const [],
  bool barrierDismissible = true,
  List<Color>? accentGradient,
}) {
  final List<Color> grad = accentGradient ?? context.gx.accentGradient;
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                color: ctx.gx.card.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ctx.gx.ink.withValues(alpha: 0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title != null) ...[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: ctx.gx.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (message != null) ...[
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: ctx.gx.ink.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (content != null) ...[
                    content,
                    const SizedBox(height: 18),
                  ],
                  for (int i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _GxDialogButton(action: actions[i], gradient: grad),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _GxDialogButton extends StatelessWidget {
  final GxDialogAction action;
  final List<Color> gradient;

  const _GxDialogButton({required this.action, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return GxPressable(
      onTap: action.onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: action.isPrimary
              ? LinearGradient(
                  colors: gradient,
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: action.isPrimary
              ? null
              : context.gx.ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: action.isPrimary
              ? null
              : Border.all(color: context.gx.ink.withValues(alpha: 0.14)),
        ),
        child: Text(
          action.label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: action.isPrimary
                ? context.gx.onAccent // sits on the primary accent gradient
                : context.gx.ink.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
