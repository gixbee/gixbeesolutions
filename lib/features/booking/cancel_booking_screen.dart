import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/booking_repository.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_dialog.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';

/// Customer cancellation flow — pick a reason, confirm, see the refund.
/// Mirrors the mockup's cancel-confirm sub-screen.
class CancelBookingScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const CancelBookingScreen({super.key, required this.bookingId});

  @override
  ConsumerState<CancelBookingScreen> createState() => _CancelBookingScreenState();
}

class _CancelBookingScreenState extends ConsumerState<CancelBookingScreen> {
  static const _reasons = [
    'Price too high',
    'Change of plans',
    'Found another vendor',
    'Event postponed',
    'Service no longer needed',
    'Other',
  ];

  String? _selected;
  bool _submitting = false;

  Future<void> _confirm() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(bookingRepositoryProvider)
          .cancelBooking(widget.bookingId, reason: _selected!);
      ref.invalidate(myBookingsProvider);
      if (!mounted) return;
      final refund = (result['refundAmount'] is num)
          ? (result['refundAmount'] as num).toDouble()
          : 0.0;
      await _showRefundDialog(refund);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not cancel. Please try again.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showRefundDialog(double refund) {
    return showGxDialog<void>(
      context,
      title: 'Booking cancelled',
      message: refund > 0
          ? '₹${refund.toStringAsFixed(0)} has been refunded to your original payment method.'
          : 'Your booking has been cancelled. No payment was captured, so there is nothing to refund.',
      actions: [
        GxDialogAction(
          'Done',
          isPrimary: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cancel booking')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Why are you cancelling?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Your feedback helps us improve.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                ..._reasons.map((r) {
                  final selected = _selected == r;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selected
                        ? context.gx.accent.withValues(alpha: 0.18)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    child: ListTile(
                      onTap: () => setState(() => _selected = r),
                      title: Text(r),
                      trailing: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected
                            ? context.gx.accent
                            : scheme.outline,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Any payment already made will be refunded to your original payment method.',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: GxButton(
                  label: 'Confirm cancellation',
                  onTap: (_selected == null || _submitting) ? null : _confirm,
                  loading: _submitting,
                  gradient: [scheme.error, scheme.error],
                  accent: scheme.error,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
