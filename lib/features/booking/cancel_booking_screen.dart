import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/booking_repository.dart';
import '../../theme.dart';
import '../../shared/widgets/gx_dialog.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_button.dart';

/// Customer cancellation flow — pick a reason, confirm, see the refund.
/// Handles late-cancel protection: request cancel when the pro has arrived,
/// warn on ACCEPTED bookings, and surface strike / block messages.
class CancelBookingScreen extends ConsumerStatefulWidget {
  final String bookingId;

  const CancelBookingScreen({super.key, required this.bookingId});

  @override
  ConsumerState<CancelBookingScreen> createState() =>
      _CancelBookingScreenState();
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
  bool _loadingBooking = true;
  String _status = '';
  bool _workerNoProgress = false;

  bool get _needsProApproval {
    final s = _status.toUpperCase();
    return s == 'ARRIVED' || s == 'ACTIVE' || s == 'IN_PROGRESS';
  }

  bool get _isAccepted => _status.toUpperCase() == 'ACCEPTED';

  bool get _freeCancelDueToNoProgress =>
      _isAccepted && _workerNoProgress;

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _status = booking?['status']?.toString() ?? '';
        _workerNoProgress = booking?['workerNoProgressAt'] != null ||
            booking?['workerNoProgress'] == true;
        _loadingBooking = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingBooking = false);
    }
  }

  String _dioMessage(Object error, {String fallback = 'Something went wrong'}) {
    if (error is DioException) {
      final data = error.response?.data;
      final raw = data is Map ? data['message'] : null;
      if (raw is String && raw.isNotEmpty) return raw;
      if (raw is List && raw.isNotEmpty) return raw.first.toString();
    }
    return fallback;
  }

  Future<void> _confirmCancel() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(bookingRepositoryProvider)
          .cancelBooking(widget.bookingId, reason: _selected!);
      ref.invalidate(myBookingsProvider);
      if (!mounted) return;
      await _showOutcomeDialog(result, cancelled: true);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showGxSnack(context, _dioMessage(e, fallback: 'Could not cancel.'),
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _requestCancel() async {
    if (_selected == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref.read(bookingRepositoryProvider).requestCancel(
            widget.bookingId,
            reason: _selected,
          );
      ref.invalidate(myBookingsProvider);
      if (!mounted) return;
      await _showOutcomeDialog(result, cancelled: false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        showGxSnack(
            context, _dioMessage(e, fallback: 'Could not send the request.'),
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showOutcomeDialog(
    Map<String, dynamic> result, {
    required bool cancelled,
  }) {
    final message = result['message']?.toString();
    final refund = (result['refundAmount'] is num)
        ? (result['refundAmount'] as num).toDouble()
        : 0.0;
    final strikeCount = (result['strikeCount'] as num?)?.toInt();
    final lateStrike = result['lateCancelStrike'] == true;
    final blocked = result['instantHelpBlocked'] == true;
    final compAmount = (result['compensationAmount'] as num?)?.toDouble();
    final compKm = (result['compensationDistanceKm'] as num?)?.toDouble();

    final parts = <String>[];
    if (message != null && message.isNotEmpty) {
      parts.add(message);
    } else if (cancelled) {
      parts.add(refund > 0
          ? '₹${refund.toStringAsFixed(0)} has been refunded to your original payment method.'
          : 'Your booking has been cancelled.');
    } else {
      parts.add('Your pro will be asked to approve the cancellation.');
    }
    if (lateStrike && strikeCount != null) {
      parts.add('Late-cancel strike $strikeCount of 3 recorded.');
    }
    if (blocked) {
      parts.add('Instant Help is blocked until travel compensation is paid.');
      if (compAmount != null && compAmount > 0) {
        final kmPart = compKm != null && compKm > 0
            ? ' (${compKm.toStringAsFixed(1)} km)'
            : '';
        parts.add('Pay ₹${compAmount.toStringAsFixed(0)}$kmPart to unlock.');
      }
    }

    return showGxDialog<void>(
      context,
      title: cancelled ? 'Booking cancelled' : 'Cancel request sent',
      message: parts.join('\n\n'),
      actions: [
        GxDialogAction(
          'Done',
          isPrimary: true,
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _infoBanner(String text, {Color? color}) {
    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final tone = color ?? gx.accent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: color ?? muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: muted)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final err = Theme.of(context).colorScheme.error;

    return Scaffold(
      backgroundColor: gx.bg,
      appBar: AppBar(title: const Text('Cancel booking')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_loadingBooking)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  if (_needsProApproval) ...[
                    _infoBanner(
                      'Your pro has already arrived or work has started. '
                      'They must approve a cancellation — you cannot cancel '
                      'unilaterally.',
                      color: err,
                    ),
                    const SizedBox(height: 16),
                  ] else if (_freeCancelDueToNoProgress) ...[
                    _infoBanner(
                      'Your pro does not appear to be heading your way. '
                      'You can cancel at no cost — no late-cancel strike.',
                      color: GixbeeTheme.accentGold,
                    ),
                    const SizedBox(height: 16),
                  ] else if (_isAccepted) ...[
                    _infoBanner(
                      'Cancelling now may count as a late cancel and add a '
                      'strike. After 3 strikes, Instant Help is blocked until '
                      'you pay travel compensation to your pro.',
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                Text('Why are you cancelling?',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: gx.ink)),
                const SizedBox(height: 4),
                Text('Your feedback helps us improve.',
                    style: TextStyle(
                        color: gx.ink.withValues(alpha: 0.55))),
                const SizedBox(height: 16),
                ..._reasons.map((r) {
                  final selected = _selected == r;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: selected
                        ? gx.accent.withValues(alpha: 0.18)
                        : gx.card2,
                    child: ListTile(
                      onTap: () => setState(() => _selected = r),
                      title: Text(r, style: TextStyle(color: gx.ink)),
                      trailing: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected ? gx.accent : gx.border,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                if (!_needsProApproval)
                  _infoBanner(
                    'Any payment already made will be refunded to your '
                    'original payment method.',
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_needsProApproval)
                    GxButton(
                      label: 'Request cancellation',
                      onTap: (_selected == null || _submitting)
                          ? null
                          : _requestCancel,
                      loading: _submitting,
                    )
                  else if (_freeCancelDueToNoProgress)
                    GxButton(
                      label: 'Cancel free',
                      onTap: (_selected == null || _submitting)
                          ? null
                          : _confirmCancel,
                      loading: _submitting,
                      gradient: [err, err],
                      accent: err,
                    )
                  else if (_isAccepted) ...[
                    GxButton(
                      label: 'Ask pro to cancel',
                      onTap: (_selected == null || _submitting)
                          ? null
                          : _requestCancel,
                      loading: _submitting,
                    ),
                    const SizedBox(height: 10),
                    GxButton(
                      label: 'Cancel anyway',
                      onTap: (_selected == null || _submitting)
                          ? null
                          : _confirmCancel,
                      loading: _submitting,
                      gradient: [err, err],
                      accent: err,
                    ),
                  ] else
                    GxButton(
                      label: 'Confirm cancellation',
                      onTap: (_selected == null || _submitting)
                          ? null
                          : _confirmCancel,
                      loading: _submitting,
                      gradient: [err, err],
                      accent: err,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
