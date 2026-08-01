import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../theme.dart';
import 'report_issue_sheet.dart';

/// Self-contained ACTIVE-job strip: live work timer + report link.
/// Drop into any screen shown during active work (completion OTP screen,
/// tracking screen…). Uses the shared [bookingStatusProvider] poll and
/// fetches `startedAt` once for the timer.
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

  @override
  Widget build(BuildContext context) {
    final statusData =
        ref.watch(bookingStatusProvider(widget.bookingId)).value;
    if (statusData != null) {
      final status = statusData['status']?.toString().toUpperCase() ?? '';
      if (status.isNotEmpty && status != 'ACTIVE' && status != 'IN_PROGRESS') {
        return const SizedBox.shrink();
      }
    }

    final cs = Theme.of(context).colorScheme;
    final accent = context.gx.accentSoft;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border, width: 1.5),
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
                          color: cs.onSurfaceVariant)),
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
