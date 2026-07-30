import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/job_credits_repository.dart';
import '../../theme.dart';

/// Job-credit ledger — every + and − with what caused it, so a worker can
/// always answer "where did my credits go": pack purchases (+3), accepts
/// (−1, named by the job's trade), and refunds (+1, customer cancel /
/// no-show).
class CreditHistoryScreen extends ConsumerStatefulWidget {
  const CreditHistoryScreen({super.key});

  @override
  ConsumerState<CreditHistoryScreen> createState() =>
      _CreditHistoryScreenState();
}

class _CreditHistoryScreenState extends ConsumerState<CreditHistoryScreen> {
  List<Map<String, dynamic>>? _rows;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rows =
          await ref.read(jobCreditsRepositoryProvider).getTransactions();
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  ({String title, IconData icon, Color color}) _describe(
      Map<String, dynamic> t) {
    final reason = (t['reason'] ?? '').toString();
    final skill = t['bookingSkill']?.toString();
    switch (reason) {
      case 'PURCHASE':
        return (
          title: 'Job pack purchased',
          icon: Icons.add_card_rounded,
          color: Colors.green,
        );
      case 'JOB_ACCEPTED':
        return (
          title: 'Job accepted${skill != null ? ' — $skill' : ''}',
          icon: Icons.work_outline_rounded,
          color: Colors.redAccent,
        );
      case 'REFUND_CUSTOMER_CANCEL':
        return (
          title: 'Refund — customer cancelled'
              '${skill != null ? ' ($skill)' : ''}',
          icon: Icons.replay_rounded,
          color: Colors.teal,
        );
      case 'REFUND_NOSHOW':
        return (
          title: 'Refund — customer no-show'
              '${skill != null ? ' ($skill)' : ''}',
          icon: Icons.replay_rounded,
          color: Colors.teal,
        );
      default:
        return (
          title: reason.isEmpty ? 'Credit adjustment' : reason,
          icon: Icons.confirmation_num_outlined,
          color: Colors.blueGrey,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: context.gx.card,
        elevation: 0,
      ),
      body: _error
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Could not load history',
                      style: TextStyle(
                          color: context.gx.ink.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _fetch, child: const Text('Retry')),
                ],
              ),
            )
          : _rows == null
              ? const Center(child: CircularProgressIndicator())
              : _rows!.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No credit activity yet.\nBuying a pack or accepting '
                          'a job will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              height: 1.5,
                              color:
                                  context.gx.ink.withValues(alpha: 0.55)),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _rows!.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final t = _rows![i];
                          final d = _describe(t);
                          final delta =
                              (num.tryParse('${t['delta'] ?? 0}') ?? 0)
                                  .toInt();
                          final when = DateTime.tryParse(
                                  '${t['createdAt'] ?? ''}')
                              ?.toLocal();
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.gx.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: context.gx.ink
                                      .withValues(alpha: 0.06)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color:
                                        d.color.withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(11),
                                  ),
                                  child: Icon(d.icon,
                                      size: 19, color: d.color),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        d.title,
                                        style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: context.gx.ink),
                                      ),
                                      if (when != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat('d MMM yyyy · h:mm a')
                                              .format(when),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: context.gx.ink
                                                  .withValues(alpha: 0.5)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Text(
                                  '${delta > 0 ? '+' : ''}$delta',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: delta > 0
                                        ? Colors.green
                                        : Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
