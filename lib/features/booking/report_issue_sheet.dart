import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// v126 Instant Help "Report / raise a concern" (c18/c20 customer, w11/w12
/// worker): reason chips + optional details, POSTed to /bookings/:id/dispute
/// (persisted server-side with reporter role + timestamp).
Future<void> showReportIssueSheet(
  BuildContext context,
  WidgetRef ref, {
  required String bookingId,
  required bool isWorker,
}) {
  final reasons = isWorker
      ? const [
          'Customer not present',
          'Unsafe situation',
          'Job differs from description',
          'Payment concern',
          'Customer behaviour',
          'Other',
        ]
      : const [
          'Work quality concern',
          'Worker behaviour',
          'Overcharging / billing',
          'Worker left mid-job',
          'Safety concern',
          'Other',
        ];

  String? selected;
  final detailsCtrl = TextEditingController();
  bool submitting = false;

  return showGxSheet<void>(
    context,
    title: 'Report an issue',
    child: StatefulBuilder(
      builder: (ctx, setSheetState) {
        Future<void> submit() async {
          if (selected == null) {
            showGxSnack(ctx, 'Please pick a reason', type: GxSnackType.error);
            return;
          }
          setSheetState(() => submitting = true);
          final details = detailsCtrl.text.trim();
          final reason =
              details.isEmpty ? selected! : '$selected — $details';
          try {
            await ref
                .read(bookingRepositoryProvider)
                .reportDispute(bookingId, reason);
            if (ctx.mounted) {
              Navigator.pop(ctx);
              showGxSnack(context, 'Report submitted — our team will review it.',
                  type: GxSnackType.success);
            }
          } catch (e) {
            if (ctx.mounted) {
              setSheetState(() => submitting = false);
              showGxSnack(ctx, 'Could not submit: $e',
                  type: GxSnackType.error);
            }
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tell us what went wrong. Reports are attached to this booking '
              'and reviewed by the Gixbee team.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: ctx.gx.ink.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in reasons)
                  ChoiceChip(
                    label: Text(r,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: selected == r
                                ? ctx.gx.onAccent
                                : ctx.gx.ink.withValues(alpha: 0.75))),
                    selected: selected == r,
                    onSelected: (_) => setSheetState(() => selected = r),
                    selectedColor: context.gx.accentSoft,
                    backgroundColor: ctx.gx.card2,
                    side: BorderSide(
                        color: selected == r
                            ? context.gx.accentSoft
                            : ctx.gx.border),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: detailsCtrl,
              maxLines: 3,
              style: TextStyle(color: ctx.gx.ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add details (optional)…',
                hintStyle:
                    TextStyle(color: ctx.gx.ink.withValues(alpha: 0.3)),
                filled: true,
                fillColor: ctx.gx.card2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ctx.gx.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: ctx.gx.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GxButton(
              label: submitting ? 'Submitting…' : 'Submit report',
              onTap: submitting ? null : submit,
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    ),
  );
}
