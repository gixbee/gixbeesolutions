import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/booking_status_provider.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';
import 'report_issue_sheet.dart';

/// Self-contained ACTIVE-job strip: live work timer + pause/resume controls +
/// report link. Drop into any screen shown during active work (completion OTP
/// screen, tracking screen…). Polls /bookings/:id/status every 5s for the
/// pause flags and fetches startedAt once for the timer, so the host screen
/// needs no wiring beyond bookingId + role.
///
/// Flow (v126): worker requests pause → customer approves (timer freezes,
/// billed time excludes it) or declines → worker resumes when work continues.
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
  // AUDIT FIX: this widget no longer runs its own status Timer — it watches
  // the shared bookingStatusProvider (one poll per booking, app-wide).
  // Only the 1s display ticker for the elapsed label remains local.
  Timer? _ticker;
  DateTime? _startedAt;
  bool _busy = false;
  Duration _elapsed = Duration.zero;

  // Latest values from the shared poll (read in build).
  bool _pauseRequested = false;
  bool _paused = false;
  int _pausedMinutes = 0;

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
    // startedAt for the timer (one full booking fetch — not a poll).
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
      if (!mounted || _paused || _startedAt == null) return;
      final worked = DateTime.now().difference(_startedAt!) -
          Duration(minutes: _pausedMinutes);
      setState(() => _elapsed = worked.isNegative ? Duration.zero : worked);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      // Refresh the shared poll immediately so the UI reflects the new state
      // without waiting for the next 5s tick.
      ref.invalidate(bookingStatusProvider(widget.bookingId));
    } catch (e) {
      if (mounted) {
        showGxSnack(context, 'Action failed: $e', type: GxSnackType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _label {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Shared poll (one per booking, app-wide) instead of a local timer.
    final statusData =
        ref.watch(bookingStatusProvider(widget.bookingId)).value;
    if (statusData != null) {
      final status = statusData['status']?.toString().toUpperCase() ?? '';
      _pauseRequested = statusData['pauseRequested'] == true;
      _paused = statusData['paused'] == true;
      _pausedMinutes =
          (statusData['pausedMinutes'] as num?)?.toInt() ?? _pausedMinutes;
      // Hide once the job leaves ACTIVE.
      if (status.isNotEmpty && status != 'ACTIVE' && status != 'IN_PROGRESS') {
        return const SizedBox.shrink();
      }
    }

    final cs = Theme.of(context).colorScheme;
    final repo = ref.read(bookingRepositoryProvider);
    final accent = _paused ? GixbeeTheme.accentGold : context.gx.accentSoft;

    Widget controls;
    if (widget.isWorker) {
      if (_paused) {
        controls = GxButton(
          label: 'Resume work — timer continues',
          icon: Icons.play_arrow_rounded,
          height: 44,
          radius: 12,
          fontSize: 13,
          onTap: _busy ? null : () => _run(() => repo.resumeWork(widget.bookingId)),
        );
      } else if (_pauseRequested) {
        controls = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Pause requested — waiting for customer',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        );
      } else {
        controls = GxButton(
          label: 'Request pause',
          icon: Icons.pause_rounded,
          filled: false,
          height: 44,
          radius: 12,
          fontSize: 13,
          onTap:
              _busy ? null : () => _run(() => repo.requestPause(widget.bookingId)),
        );
      }
    } else {
      if (_pauseRequested) {
        controls = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your pro asked to pause the job timer',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GxButton(
                    label: 'Approve pause',
                    height: 44,
                    radius: 12,
                    fontSize: 13,
                    onTap: _busy
                        ? null
                        : () => _run(() =>
                            repo.respondPause(widget.bookingId, approve: true)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GxButton(
                    label: 'Decline',
                    filled: false,
                    height: 44,
                    radius: 12,
                    fontSize: 13,
                    onTap: _busy
                        ? null
                        : () => _run(() =>
                            repo.respondPause(widget.bookingId, approve: false)),
                  ),
                ),
              ],
            ),
          ],
        );
      } else if (_paused) {
        controls = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pause_circle_outline_rounded,
                size: 16, color: GixbeeTheme.accentGold),
            const SizedBox(width: 8),
            Text('Paused — resumes when your pro continues',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ],
        );
      } else {
        controls = const SizedBox.shrink();
      }
    }

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
                  Icon(
                    _paused
                        ? Icons.pause_circle_outline_rounded
                        : Icons.timer_outlined,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Text(_paused ? 'Job timer · paused' : 'Job timer',
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
          if (controls is! SizedBox) ...[
            const SizedBox(height: 12),
            controls,
          ],
          const SizedBox(height: 2),
          Center(
            child: TextButton.icon(
              onPressed: () => showReportIssueSheet(context, ref,
                  bookingId: widget.bookingId, isWorker: widget.isWorker),
              icon: Icon(Icons.flag_outlined,
                  size: 14, color: context.gx.ink.withValues(alpha: 0.5)),
              label: Text('Report an issue',
                  style: TextStyle(
                      fontSize: 12, color: context.gx.ink.withValues(alpha: 0.5))),
            ),
          ),
        ],
      ),
    );
  }
}
