import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme.dart';
import '../../repositories/worker_repository.dart';
import '../../shared/widgets/dribbble_background.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_pressable.dart';
import '../../shared/widgets/gx_sheet.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Fair-penalty ledger: every strike a worker receives — with the written
/// reason, the appeal state, and a one-tap appeal form. Backed by
/// GET /workers/me/strikes + POST /workers/me/strikes/:id/appeal.
///
/// Design intent (worker trust): a worker must NEVER discover they're
/// suspended without being able to read exactly why and answer back. This is
/// the screen every strike push notification deep-links to in spirit
/// ("Profile → Strikes").
class StrikesScreen extends ConsumerWidget {
  const StrikesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strikesAsync = ref.watch(myStrikesProvider);

    return Scaffold(
      backgroundColor: context.gx.bg,
      body: DribbbleBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: context.gx.ink),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Strikes & Appeals',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: context.gx.ink)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: strikesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorState(
                    onRetry: () => ref.invalidate(myStrikesProvider),
                  ),
                  data: (data) => _StrikesBody(data: data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrikesBody extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _StrikesBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strikes = (data['strikes'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final count = (data['strikeCount'] as num?)?.toInt() ?? 0;
    final threshold = (data['threshold'] as num?)?.toInt() ?? 3;
    final suspended = data['suspended'] == true;

    if (strikes.isEmpty && count == 0) {
      return _CleanRecordState(threshold: threshold);
    }

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myStrikesProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _SummaryCard(
              count: count, threshold: threshold, suspended: suspended),
          const SizedBox(height: 16),
          for (final strike in strikes) ...[
            _StrikeCard(strike: strike),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int count;
  final int threshold;
  final bool suspended;
  const _SummaryCard(
      {required this.count, required this.threshold, required this.suspended});

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFEF4444);
    final color = suspended
        ? red
        : count > 0
            ? const Color(0xFFF97316)
            : const Color(0xFF22C55E);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
              suspended
                  ? Icons.block_rounded
                  : Icons.report_gmailerrorred_rounded,
              color: color,
              size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suspended
                      ? 'Suspended from going live'
                      : '$count of $threshold strikes',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: context.gx.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  suspended
                      ? 'Appeal a strike below — if it\'s overturned and you '
                          'drop under $threshold, Go Live unlocks immediately.'
                      : 'At $threshold strikes you\'ll be suspended from '
                          'going live. Every strike can be appealed once.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.gx.ink.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StrikeCard extends ConsumerWidget {
  final Map<String, dynamic> strike;
  const _StrikeCard({required this.strike});

  static const _statusInfo = {
    'ACTIVE': ('Counts toward suspension', Color(0xFFF97316)),
    'APPEALED': ('Appeal under review', Color(0xFF0EA5E9)),
    'OVERTURNED': ('Overturned — doesn\'t count', Color(0xFF22C55E)),
    'UPHELD': ('Appeal reviewed — strike stands', Color(0xFFEF4444)),
  };

  static const _typeLabels = {
    'GPS_FORFEIT': 'Job forfeited (GPS)',
    'NO_SHOW': 'No-show',
    'ADMIN': 'Policy violation',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = (strike['status'] ?? 'ACTIVE').toString();
    final (statusLabel, statusColor) =
        _statusInfo[status] ?? ('Recorded', const Color(0xFFF97316));
    final type = (strike['type'] ?? '').toString();
    final createdAt = DateTime.tryParse('${strike['createdAt'] ?? ''}');
    final resolutionNote = (strike['resolutionNote'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.gx.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.gx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _typeLabels[type] ?? 'Strike',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.gx.ink),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor),
                ),
              ),
            ],
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${createdAt.day.toString().padLeft(2, '0')}/'
              '${createdAt.month.toString().padLeft(2, '0')}/'
              '${createdAt.year}',
              style: TextStyle(
                  fontSize: 11,
                  color: context.gx.ink.withValues(alpha: 0.45)),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            (strike['reason'] ?? 'No reason recorded.').toString(),
            style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: context.gx.ink.withValues(alpha: 0.75)),
          ),
          if (resolutionNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.gx.card2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Gixbee team: $resolutionNote',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                    color: context.gx.ink.withValues(alpha: 0.65)),
              ),
            ),
          ],
          if (status == 'ACTIVE') ...[
            const SizedBox(height: 12),
            GxPressable(
              onTap: () => _openAppealSheet(context, ref),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: context.gx.accentSoft.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: context.gx.accentSoft.withValues(alpha: 0.4)),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Appeal this strike',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: context.gx.accentSoft),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAppealSheet(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    var submitting = false;
    showGxSheet<void>(
      context,
      title: 'Appeal this strike',
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell us what actually happened — GPS issues, the customer '
                'cancelled at the door, a family emergency. A real person '
                'reads every appeal.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ctx.gx.ink.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                maxLength: 1000,
                style: TextStyle(color: ctx.gx.ink, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Your side of the story…',
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
              const SizedBox(height: 12),
              GxButton(
                label: submitting ? 'Submitting…' : 'Submit appeal',
                onTap: submitting
                    ? null
                    : () async {
                        final message = ctrl.text.trim();
                        if (message.isEmpty) {
                          showGxSnack(
                              ctx, 'Please describe what happened first',
                              type: GxSnackType.error);
                          return;
                        }
                        setSheetState(() => submitting = true);
                        try {
                          final result = await ref
                              .read(workerRepositoryProvider)
                              .appealStrike('${strike['id']}', message);
                          ref.invalidate(myStrikesProvider);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            showGxSnack(ctx, result,
                                type: GxSnackType.success);
                          }
                        } catch (e) {
                          setSheetState(() => submitting = false);
                          if (ctx.mounted) {
                            showGxSnack(ctx, 'Could not submit appeal: $e',
                                type: GxSnackType.error);
                          }
                        }
                      },
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _CleanRecordState extends StatelessWidget {
  final int threshold;
  const _CleanRecordState({required this.threshold});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified_rounded,
                size: 64, color: Color(0xFF22C55E)),
            const SizedBox(height: 16),
            Text('Clean record',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: context.gx.ink)),
            const SizedBox(height: 8),
            Text(
              'No strikes on your account. Strikes are issued for forfeited '
              'jobs and no-shows; $threshold strikes suspends Go Live. Every '
              'strike comes with a written reason and can be appealed.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.gx.ink.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 48, color: context.gx.ink.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('Couldn\'t load your strikes',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: context.gx.ink)),
          const SizedBox(height: 14),
          GxPressable(
            onTap: onRetry,
            child: Text('Try again',
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: context.gx.accentSoft)),
          ),
        ],
      ),
    );
  }
}
