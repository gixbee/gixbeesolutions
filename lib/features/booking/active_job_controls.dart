import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../theme.dart';
import 'cancel_request_actions.dart';
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

  Future<void> _loadStartedAt() async {
    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .getBookingById(widget.bookingId);
      final raw = booking?['startedAt']?.toString();
      if (raw != null && raw.isNotEmpty) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null && mounted) {
          setState(() => _startedAt = parsed);
        }
      }
    } catch (e) {
      debugPrint('ActiveJobControls startedAt fetch failed: $e');
    }
  }

  Future<void> _init() async {
    await _loadStartedAt();
    if (!mounted) return;
    _ticker?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final statusData =
        ref.watch(bookingStatusProvider(widget.bookingId)).value;
    final status = statusData?['status']?.toString().toUpperCase() ?? '';

    // Status poll may carry startedAt before GET /bookings/:id is refreshed.
    if (_startedAt == null) {
      final fromPoll = statusData?['startedAt']?.toString();
      if (fromPoll != null && fromPoll.isNotEmpty) {
        final parsed = DateTime.tryParse(fromPoll);
        if (parsed != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _startedAt = parsed);
          });
        }
      } else if (status == 'ACTIVE' || status == 'IN_PROGRESS') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_loadStartedAt());
        });
      }
    }

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
          CancelRequestActions(
            bookingId: widget.bookingId,
            isWorker: widget.isWorker,
            allowRequest: true,
          ),
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
