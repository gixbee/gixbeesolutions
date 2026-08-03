import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../shared/utils/api_error_message.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import '../home/active_booking_card.dart';

/// Which cancel-request call is in flight — each button owns its own spinner.
enum _CancelAction { request, withdraw, approve, decline }

/// Pending cancel-request controls for a live job, for both roles:
///   • worker → Approve / Decline the customer's request
///   • customer → "waiting for your pro" + Withdraw
///
/// Self-gating: reads the shared booking-status stream, so any screen that
/// shows a live job can mount it without threading state through.
/// Renders nothing when there is no request to act on.
class CancelRequestActions extends ConsumerStatefulWidget {
  final String bookingId;
  final bool isWorker;

  /// Show "Request cancellation" to the customer when nothing is pending.
  /// Screens that already have their own cancel entry point pass false.
  final bool allowRequest;

  /// Set by screens that hold a booking snapshot and must not start a status
  /// poll of their own; they own the status gate too. Null → watch the stream.
  final bool? cancelRequested;

  /// Called after a successful action — lets a snapshot screen close itself
  /// rather than keep showing stale controls.
  final VoidCallback? onActionCompleted;

  const CancelRequestActions({
    super.key,
    required this.bookingId,
    required this.isWorker,
    this.allowRequest = false,
    this.cancelRequested,
    this.onActionCompleted,
  });

  @override
  ConsumerState<CancelRequestActions> createState() =>
      _CancelRequestActionsState();
}

class _CancelRequestActionsState extends ConsumerState<CancelRequestActions> {
  static const _liveStatuses = {'ACCEPTED', 'ARRIVED', 'ACTIVE', 'IN_PROGRESS'};

  _CancelAction? _busy;

  bool get _anyBusy => _busy != null;

  Future<void> _run(
    _CancelAction action,
    Future<void> Function() call, {
    required String success,
    required String failure,
    GxSnackType successType = GxSnackType.success,
  }) async {
    if (_anyBusy) return;
    setState(() => _busy = action);
    try {
      await call();
      ref.invalidate(myBookingsProvider);
      ref.invalidate(activeBookingProvider);
      ref.read(bookingStatusNudgeProvider).poke(widget.bookingId);
      if (mounted) showGxSnack(context, success, type: successType);
      widget.onActionCompleted?.call();
    } catch (e) {
      if (mounted) {
        showGxSnack(context, apiErrorMessage(e, fallback: failure),
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _request() => _run(
        _CancelAction.request,
        () => ref
            .read(bookingRepositoryProvider)
            .requestCancel(widget.bookingId)
            .then((_) {}),
        success: 'Cancel request sent to your pro.',
        failure: 'Could not send cancel request.',
      );

  Future<void> _withdraw() => _run(
        _CancelAction.withdraw,
        () => ref
            .read(bookingRepositoryProvider)
            .withdrawCancelRequest(widget.bookingId)
            .then((_) {}),
        success: 'Cancel request withdrawn.',
        failure: 'Could not withdraw request.',
      );

  Future<void> _approve() => _run(
        _CancelAction.approve,
        () => ref
            .read(bookingRepositoryProvider)
            .approveCancel(widget.bookingId)
            .then((_) {}),
        success: 'Cancellation approved.',
        failure: 'Could not approve cancellation.',
      );

  Future<void> _decline() => _run(
        _CancelAction.decline,
        () => ref
            .read(bookingRepositoryProvider)
            .declineCancel(widget.bookingId)
            .then((_) {}),
        success: 'Cancel request declined.',
        failure: 'Could not decline request.',
        successType: GxSnackType.info,
      );

  @override
  Widget build(BuildContext context) {
    bool cancelRequested;
    if (widget.cancelRequested != null) {
      cancelRequested = widget.cancelRequested!;
    } else {
      final statusData =
          ref.watch(bookingStatusProvider(widget.bookingId)).value;
      final status = statusData?['status']?.toString().toUpperCase() ?? '';
      if (!_liveStatuses.contains(status)) return const SizedBox.shrink();
      cancelRequested = statusData?['cancelRequested'] == true;
    }

    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final err = Theme.of(context).colorScheme.error;

    if (widget.isWorker) {
      if (!cancelRequested) return const SizedBox.shrink();
      return _Section(
        children: [
          _Caption('Customer requested cancellation', color: muted, bold: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Decline',
                  onTap: _anyBusy ? null : _decline,
                  loading: _busy == _CancelAction.decline,
                  // Outline: a filled pill forces the white onAccent label,
                  // which disappears on the light card fill.
                  filled: false,
                  accent: gx.ink.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GxButton(
                  label: 'Approve',
                  onTap: _anyBusy ? null : _approve,
                  loading: _busy == _CancelAction.approve,
                  gradient: [err, err],
                  accent: err,
                ),
              ),
            ],
          ),
        ],
      );
    }

    if (cancelRequested) {
      return _Section(
        children: [
          _Caption('Waiting for your pro to approve cancellation…',
              color: muted),
          const SizedBox(height: 8),
          GxButton(
            label: 'Withdraw request',
            onTap: _anyBusy ? null : _withdraw,
            loading: _busy == _CancelAction.withdraw,
          ),
        ],
      );
    }

    if (!widget.allowRequest) return const SizedBox.shrink();

    return _Section(
      children: [
        GxButton(
          label: 'Request cancellation',
          onTap: _anyBusy ? null : _request,
          loading: _busy == _CancelAction.request,
          gradient: [err.withValues(alpha: 0.85), err],
          accent: err,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const SizedBox(height: 10), ...children],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {required this.color, this.bold = false});

  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: color,
      ),
    );
  }
}
