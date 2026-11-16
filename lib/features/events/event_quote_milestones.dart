import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Acknowledgements track *direct* payment and delivery.
/// This screen never initiates a transaction.
class EventQuoteMilestones extends ConsumerStatefulWidget {
  const EventQuoteMilestones({
    super.key,
    required this.quoteId,
    required this.customer,
    required this.status,
    this.onChanged,
  });

  final String quoteId;
  final bool customer;
  final String status;
  final VoidCallback? onChanged;

  @override
  ConsumerState<EventQuoteMilestones> createState() =>
      _EventQuoteMilestonesState();
}

class _EventQuoteMilestonesState extends ConsumerState<EventQuoteMilestones> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _future =
        ref.read(eventsRepositoryProvider).quoteMilestones(widget.quoteId);
  }

  Future<void> _reload() async {
    setState(_load);
    try {
      await _future;
    } catch (_) {
      // FutureBuilder displays the latest error.
    }
  }

  Future<void> _acknowledge(Map<String, dynamic> item) async {
    if (_busy) return;
    final kind = item['kind']?.toString() ?? '';
    final action = kind == 'PAYMENT'
        ? (widget.customer ? 'Confirm money sent?' : 'Confirm money received?')
        : (widget.customer
            ? 'Confirm delivery received?'
            : 'Confirm delivery sent?');
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action),
        content: const Text(
          'This records your acknowledgement only. No funds are transferred by Gixbee. '
          'The other participant must confirm independently.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(eventsRepositoryProvider)
          .acknowledgeQuoteMilestone(widget.quoteId, item['id'] as String);
      if (!mounted) return;
      await _reload();
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createSchedule() async {
    if (_busy) return;
    final advance = TextEditingController(text: '30');
    final delivery = TextEditingController();
    final details = TextEditingController();
    List<Map<String, dynamic>>? planned;
    try {
      planned = await showDialog<List<Map<String, dynamic>>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Milestone schedule'),
          content: SizedBox(
              width: 390,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Create an agreed direct-payment and deliverable plan. '
                      'Payments are arranged outside Gixbee.'),
                  const SizedBox(height: 12),
                  TextField(
                      controller: advance,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Advance percentage',
                        helperText:
                            '0 = no payment milestones; 100 = one full payment',
                        border: OutlineInputBorder(),
                      )),
                  const SizedBox(height: 12),
                  TextField(
                      controller: delivery,
                      maxLength: 150,
                      decoration: const InputDecoration(
                        labelText: 'Deliverable milestone (optional)',
                        hintText: 'Edited photos, albums, final service',
                        border: OutlineInputBorder(),
                      )),
                  const SizedBox(height: 12),
                  TextField(
                      controller: details,
                      maxLength: 3000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Deliverable details',
                        border: OutlineInputBorder(),
                      )),
                ]),
              )),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final percentage = int.tryParse(advance.text.trim());
                if (percentage == null || percentage < 0 || percentage > 100) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Advance must be between 0 and 100%.')));
                  return;
                }
                final rows = <Map<String, dynamic>>[];
                if (percentage > 0 && percentage < 100) {
                  rows.addAll([
                    {
                      'kind': 'PAYMENT',
                      'label': 'Booking advance',
                      'percent': percentage
                    },
                    {
                      'kind': 'PAYMENT',
                      'label': 'Balance',
                      'percent': 100 - percentage
                    },
                  ]);
                } else if (percentage == 100) {
                  rows.add({
                    'kind': 'PAYMENT',
                    'label': 'Full direct payment',
                    'percent': 100
                  });
                }
                if (delivery.text.trim().isNotEmpty) {
                  rows.add({
                    'kind': 'DELIVERY',
                    'label': delivery.text.trim(),
                    'details': details.text.trim()
                  });
                }
                if (rows.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                          content:
                              Text('Add a payment or deliverable milestone.')));
                  return;
                }
                Navigator.pop(dialogContext, rows);
              },
              child: const Text('Publish schedule'),
            ),
          ],
        ),
      );
    } finally {
      advance.dispose();
      delivery.dispose();
      details.dispose();
    }
    if (!mounted || planned == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(eventsRepositoryProvider)
          .createQuoteMilestones(widget.quoteId, planned);
      if (!mounted) return;
      await _reload();
      widget.onChanged?.call();
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _milestone(Map<String, dynamic> item) {
    final payment = item['kind'] == 'PAYMENT';
    final done = item['completedAt'] != null;
    final already = item[widget.customer
            ? 'customerAcknowledgedAt'
            : 'vendorAcknowledgedAt'] !=
        null;
    final otherAck = item[widget.customer
            ? 'vendorAcknowledgedAt'
            : 'customerAcknowledgedAt'] !=
        null;
    final overdue = item['overdue'] == true;
    return Card(
      color: done ? const Color(0xFFECFDF3) : Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(
                payment
                    ? Icons.payments_outlined
                    : Icons.photo_library_outlined,
                color:
                    done ? const Color(0xFF047857) : const Color(0xFF1B2559)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(item['label']?.toString() ?? 'Milestone',
                    style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
          if (payment) Text(eventMoney(item['amount'])),
          if ((item['details']?.toString() ?? '').isNotEmpty)
            Text(item['details'].toString(),
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          if (item['dueAt'] != null)
            Text(
                'Due: ${eventDate(item['dueAt'])}${overdue ? ' · Overdue' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: overdue ? Colors.red : Colors.blueGrey)),
          const SizedBox(height: 5),
          Text(
              'You: ${already ? 'Acknowledged' : 'Pending'} · '
              'Other party: ${otherAck ? 'Acknowledged' : 'Pending'}',
              style: const TextStyle(fontSize: 12)),
          if (done)
            const Text('Completed by both parties',
                style: TextStyle(
                    color: Color(0xFF047857), fontWeight: FontWeight.w700))
          else if (!already && widget.status == 'CONFIRMED')
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _acknowledge(item),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(payment
                    ? (widget.customer ? 'I paid' : 'I received')
                    : (widget.customer ? 'I received files' : 'I delivered')),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.all(8), child: LinearProgressIndicator());
          }
          if (snapshot.hasError) {
            return TextButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Unable to load milestones — retry'),
            );
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty && widget.customer) {
            return const Text(
                'No payment or delivery milestone schedule has been published.');
          }
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text('Payment & delivery milestones',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text(
                    'Direct-pay acknowledgements only; Gixbee does not collect these funds.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                const SizedBox(height: 10),
                for (final item in items) _milestone(item),
                if (items.isEmpty &&
                    widget.status == 'CONFIRMED' &&
                    !widget.customer)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _createSchedule,
                    icon: const Icon(Icons.add),
                    label: const Text('Create payment / delivery schedule'),
                  ),
              ]);
        },
      );
}
