import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme.dart';

/// Gixbee 2026 design language — branded glass bottom sheet.
/// Use for secondary actions (filters, pickers, confirmations, "all
/// services") instead of dialogs or full-screen pushes.
Future<T?> showGxSheet<T>(
  BuildContext context, {
  String? title,
  required Widget child,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 10,
              bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: ctx.gx.card.withValues(alpha: 0.92),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border:
                  Border.all(color: ctx.gx.ink.withValues(alpha: 0.10)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: ctx.gx.ink.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (title != null) ...[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: ctx.gx.ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
