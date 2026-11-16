import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_enquiry_repository.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../events/event_plan_detail_screen.dart';

/// Business-level inbox (owner). When [hallId] is set, shows assigned-only
/// list (operators see readOnly).
class HallEnquiriesInboxScreen extends ConsumerStatefulWidget {
  const HallEnquiriesInboxScreen({
    super.key,
    required this.business,
    this.hallId,
  });
  final Business business;
  final String? hallId;

  @override
  ConsumerState<HallEnquiriesInboxScreen> createState() =>
      _HallEnquiriesInboxScreenState();
}

class _HallEnquiriesInboxScreenState
    extends ConsumerState<HallEnquiriesInboxScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(hallEnquiryRepositoryProvider);
      final items = widget.hallId == null
          ? await repo.listBusiness(widget.business.id)
          : await repo.listForHall(widget.business.id, widget.hallId!);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _approve(String id) async {
    try {
      await ref
          .read(hallEnquiryRepositoryProvider)
          .approve(widget.business.id, id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _decline(String id) async {
    try {
      await ref
          .read(hallEnquiryRepositoryProvider)
          .decline(widget.business.id, id);
      _load();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _assign(Map<String, dynamic> e) async {
    final halls =
        (await ref.read(hallRepositoryProvider).listHalls(widget.business.id))
            .where((hall) => e['requestedHallId'] == null || hall['id'] == e['requestedHallId'])
            .toList();
    final ready = halls.where((h) => h['packageSaved'] == true).toList();
    if (!mounted) return;
    if (ready.isEmpty) {
      showGxSnack(context, 'Save a package on a hall first',
          type: GxSnackType.error);
      return;
    }
    final hallId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final h in ready)
            ListTile(
              title: Text((h['name'] as String?) ?? 'Hall'),
              onTap: () => Navigator.pop(ctx, h['id'] as String),
            ),
        ],
      ),
    );
    if (hallId == null) return;
    final start = DateTime.tryParse(e['startTime']?.toString() ?? '') ??
        DateTime.now().add(const Duration(days: 14));
    final end = DateTime.tryParse(e['endTime']?.toString() ?? '') ??
        start.add(const Duration(hours: 5));
    try {
      await ref.read(hallEnquiryRepositoryProvider).assignHall(
            businessId: widget.business.id,
            enquiryId: e['id'] as String,
            hallId: hallId,
            proposedStart: start,
            proposedEnd: end,
          );
      if (!mounted) return;
      showGxSnack(context, 'Hall assigned');
      await _openQuote(e['eventPlanId'] as String);
    } catch (err) {
      if (!mounted) return;
      showGxSnack(context, '$err', type: GxSnackType.error);
    }
  }

  Future<void> _openQuote(String planId) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => EventPlanDetailScreen(
        planId: planId,
        business: widget.business,
      ),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hallScoped = widget.hallId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(hallScoped ? 'Hall requests' : 'Hall enquiries'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('No enquiries yet'))
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _items[i];
                    final status = e['status']?.toString() ?? '';
                    final readOnly = e['readOnly'] == true;
                    final tz = e['venueTimezone']?.toString() ?? 'Asia/Kolkata';
                    final unassigned = e['assignedHallId'] == null;
                    final canOpenQuote = !readOnly &&
                        !unassigned &&
                        const ['ASSIGNED', 'QUOTE_OFFERED'].contains(status);
                    return ListTile(
                      onTap: canOpenQuote
                          ? () => _openQuote(e['eventPlanId'] as String)
                          : null,
                      title: Text(
                        '${e['eventType'] ?? 'Event'} · $status',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${e['startTime'] ?? ''} · ${e['guestCount'] ?? '?'} guests\n'
                        'Times in $tz'
                        '${unassigned && !hallScoped ? '\nUnassigned — business inbox' : ''}'
                        '${e['hallName'] != null ? '\nHall: ${e['hallName']}' : ''}'
                        '${unassigned && e['requestedHallName'] != null ? '\nRequested: ${e['requestedHallName']}' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: readOnly || hallScoped
                          ? (canOpenQuote ? const Icon(Icons.chevron_right) : null)
                          : PopupMenuButton<String>(
                              onSelected: (v) {
                                final id = e['id'] as String;
                                if (v == 'approve') _approve(id);
                                if (v == 'decline') _decline(id);
                                if (v == 'assign') _assign(e);
                                if (v == 'quote') _openQuote(e['eventPlanId'] as String);
                              },
                              itemBuilder: (_) => [
                                if (status == 'PENDING_OWNER') ...[
                                  const PopupMenuItem(
                                      value: 'approve', child: Text('Approve')),
                                  const PopupMenuItem(
                                      value: 'decline', child: Text('Decline')),
                                ],
                                if (['OWNER_APPROVED', 'ASSIGNED', 'QUOTE_OFFERED']
                                    .contains(status))
                                  const PopupMenuItem(
                                      value: 'assign',
                                      child: Text('Assign / reassign hall')),
                                if (canOpenQuote)
                                  const PopupMenuItem(
                                      value: 'quote',
                                      child: Text('Open quote')),
                              ],
                            ),
                    );
                  },
                ),
    );
  }
}
