import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'report_issue_sheet.dart';

/// Self-contained ACTIVE-job strip: live work timer, cancel-request controls,
/// and report link. Drop into any screen shown during active work.
class ActiveJobControls extends ConsumerStatefulWidget {
  final String bookingId;
  final bool isWorker;

  const ActiveJobControls({
    super.key,
    required this.bookingId,
    required this.isWorker,
  });

  @override
  ConsumerState<ActiveJobControls> createState() => _ActiveJobControlsState();
}

class _ActiveJobControlsState extends ConsumerState<ActiveJobControls> {
  Timer? _ticker;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _cancelBusy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      final raw = booking?['startedAt']?.toString();
      if (raw != null) _startedAt = DateTime.tryParse(raw);
    } catch (e) {
      debugPrint('ActiveJobControls startedAt fetch failed: $e');
    }
    if (!mounted) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _startedAt == null) return;
      final worked = DateTime.now().difference(_startedAt!);
      setState(() => _elapsed = worked.isNegative ? Duration.zero : worked);
    });
  }

  String get _label {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _requestCancel() async {
    if (_cancelBusy) return;
    setState(() => _cancelBusy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .requestCancel(widget.bookingId);
      ref.invalidate(bookingStatusProvider(widget.bookingId));
      if (mounted) {
        showGxSnack(context, 'Cancel request sent to your pro.',
            type: GxSnackType.success);
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not send cancel request.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _withdrawCancel() async {
    if (_cancelBusy) return;
    setState(() => _cancelBusy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .withdrawCancelRequest(widget.bookingId);
      ref.invalidate(bookingStatusProvider(widget.bookingId));
      if (mounted) {
        showGxSnack(context, 'Cancel request withdrawn.',
            type: GxSnackType.success);
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not withdraw request.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _approveCancel() async {
    if (_cancelBusy) return;
    setState(() => _cancelBusy = true);
    try {
      await ref.read(bookingRepositoryProvider).approveCancel(widget.bookingId);
      ref.invalidate(myBookingsProvider);
      ref.invalidate(bookingStatusProvider(widget.bookingId));
      if (mounted) {
        showGxSnack(context, 'Cancellation approved.',
            type: GxSnackType.success);
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not approve cancellation.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _declineCancel() async {
    if (_cancelBusy) return;
    setState(() => _cancelBusy = true);
    try {
      await ref.read(bookingRepositoryProvider).declineCancel(widget.bookingId);
      ref.invalidate(bookingStatusProvider(widget.bookingId));
      if (mounted) {
        showGxSnack(context, 'Cancel request declined.',
            type: GxSnackType.info);
      }
    } catch (_) {
      if (mounted) {
        showGxSnack(context, 'Could not decline request.',
            type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Widget _cancelRequestSection(bool cancelRequested) {
    final gx = context.gx;
    final muted = gx.ink.withValues(alpha: 0.55);
    final err = Theme.of(context).colorScheme.error;

    if (widget.isWorker) {
      if (!cancelRequested) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Text('Customer requested cancellation',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: muted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GxButton(
                  label: 'Decline',
                  onTap: _cancelBusy ? null : _declineCancel,
                  loading: _cancelBusy,
                  gradient: [gx.card2, gx.card2],
                  accent: muted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GxButton(
                  label: 'Approve',
                  onTap: _cancelBusy ? null : _approveCancel,
                  loading: _cancelBusy,
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Text('Waiting for your pro to approve cancellation…',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: muted)),
          const SizedBox(height: 8),
          GxButton(
            label: 'Withdraw request',
            onTap: _cancelBusy ? null : _withdrawCancel,
            loading: _cancelBusy,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        GxButton(
          label: 'Request cancellation',
          onTap: _cancelBusy ? null : _requestCancel,
          loading: _cancelBusy,
          gradient: [err.withValues(alpha: 0.85), err],
          accent: err,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusData =
        ref.watch(bookingStatusProvider(widget.bookingId)).value;
    final status = statusData?['status']?.toString().toUpperCase() ?? '';
    final cancelRequested = statusData?['cancelRequested'] == true;
    final showCancelControls = status == 'ARRIVED' ||
        status == 'ACTIVE' ||
        status == 'IN_PROGRESS';

    if (status.isNotEmpty &&
        status != 'ACTIVE' &&
        status != 'IN_PROGRESS' &&
        status != 'ARRIVED') {
      return const SizedBox.shrink();
    }

    final gx = context.gx;
    final accent = gx.accentSoft;
    final muted = gx.ink.withValues(alpha: 0.55);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: gx.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('Job timer',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: muted)),
                ],
              ),
              Text(_label,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: accent)),
            ],
          ),
          if (showCancelControls)
            _cancelRequestSection(cancelRequested),
          const SizedBox(height: 2),
          Center(
            child: TextButton.icon(
              onPressed: () => showReportIssueSheet(context, ref,
                  bookingId: widget.bookingId, isWorker: widget.isWorker),
              icon: Icon(Icons.flag_outlined,
                  size: 14, color: context.gx.ink.withValues(alpha: 0.5)),
              label: Text('Report an issue',
                  style: TextStyle(
                      fontSize: 12,
                      color: context.gx.ink.withValues(alpha: 0.5))),
            ),
          ),
        ],
      ),
    );
  }
}
