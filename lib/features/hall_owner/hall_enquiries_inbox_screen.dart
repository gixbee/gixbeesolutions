import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/events_repository.dart';
import '../../repositories/hall_enquiry_repository.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/utils/api_error_message.dart';
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
      showGxSnack(context, apiErrorMessage(e, fallback: 'Could not load hall enquiries.'),
          type: GxSnackType.error);
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
      showGxSnack(context, apiErrorMessage(e, fallback: 'Could not accept this request.'),
          type: GxSnackType.error);
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
      showGxSnack(context, apiErrorMessage(e, fallback: 'Could not reject this request.'),
          type: GxSnackType.error);
    }
  }

  Future<void> _assign(Map<String, dynamic> e) async {
    final halls = (await ref
            .read(hallRepositoryProvider)
            .listHalls(widget.business.id))
        .where((hall) =>
            e['requestedHallId'] == null || hall['id'] == e['requestedHallId'])
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
      showGxSnack(
        context,
        apiErrorMessage(err, fallback: 'Could not assign this hall.'),
        type: GxSnackType.error,
      );
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

  String _statusLabel(String status) => switch (status) {
        'PENDING_OWNER' => 'New request',
        'OWNER_APPROVED' => 'Approved · Assign hall',
        'ASSIGNED' => 'Hall assigned',
        'QUOTE_OFFERED' => 'Quote sent',
        'OWNER_DECLINED' => 'Declined',
        _ => status.replaceAll('_', ' ').toLowerCase(),
      };

  Color _statusColor(String status) => switch (status) {
        'PENDING_OWNER' => const Color(0xFF92400E),
        'OWNER_APPROVED' => const Color(0xFF1D4ED8),
        'ASSIGNED' || 'QUOTE_OFFERED' => const Color(0xFF047857),
        'OWNER_DECLINED' => Colors.red.shade700,
        _ => const Color(0xFF64748B),
      };

  Widget _detailRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(color: Color(0xFF475569), fontSize: 13))),
        ]),
      );

  Widget _requestCard(Map<String, dynamic> e, bool hallScoped) {
    final status = e['status']?.toString() ?? '';
    final readOnly = e['readOnly'] == true;
    final unassigned = e['assignedHallId'] == null;
    final id = e['id'] as String;
    final planId = e['eventPlanId'] as String;
    final canOpenQuote = !readOnly &&
        !unassigned &&
        const ['ASSIGNED', 'QUOTE_OFFERED'].contains(status);
    final tz = e['venueTimezone']?.toString() ?? 'Asia/Kolkata';
    final color = _statusColor(status);
    return Card(
      margin: const EdgeInsets.only(bottom: 13),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0))),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(e['eventType']?.toString() ?? 'Event booking',
                    style: const TextStyle(
                        fontSize: 17,
                        color: Color(0xFF1B2559),
                        fontWeight: FontWeight.w900))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(25)),
              child: Text(_statusLabel(status),
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 12),
          _detailRow(Icons.event, 'Start: ${eventDate(e['startTime'])}'),
          _detailRow(Icons.group_outlined,
              '${e['guestCount'] ?? '?'} guests · Times in $tz'),
          if (e['requestedHallName'] != null)
            _detailRow(
                Icons.apartment, 'Requested hall: ${e['requestedHallName']}'),
          if (e['hallName'] != null)
            _detailRow(
                Icons.meeting_room_outlined, 'Assigned hall: ${e['hallName']}'),
          if (unassigned && !hallScoped)
            const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('This enquiry has not been assigned to a hall.',
                    style: TextStyle(
                        color: Color(0xFFB45309),
                        fontWeight: FontWeight.w700))),
          if (readOnly)
            const Text(
                'View-only access · Package and approval changes require owner access.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
          if (!readOnly && !hallScoped) ...[
            const Divider(height: 22),
            if (status == 'PENDING_OWNER')
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                  icon: const Icon(Icons.close),
                  onPressed: () => _decline(id),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  onPressed: () => _approve(id),
                  label: const Text('Accept Request'),
                )),
              ]),
            if (const ['OWNER_APPROVED', 'ASSIGNED', 'QUOTE_OFFERED']
                .contains(status))
              SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.meeting_room_outlined),
                    label: Text(unassigned ? 'Assign a hall' : 'Reassign hall'),
                    onPressed: () => _assign(e),
                  )),
            if (canOpenQuote)
              SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Open quote / booking details'),
                    onPressed: () => _openQuote(planId),
                  )),
          ] else if (canOpenQuote)
            TextButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: const Text('View quote'),
              onPressed: () => _openQuote(planId),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hallScoped = widget.hallId != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(hallScoped ? 'Hall booking requests' : 'Hall enquiries'),
        actions: [
          IconButton(
            tooltip: 'Refresh requests',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Text('${_items.length} requests',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF1B2559))),
                  const SizedBox(height: 6),
                  const Text(
                      'Review requests, assign a suitable hall, then send a quote. '
                      'Payment is arranged directly between customer and venue.',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  const SizedBox(height: 16),
                  if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child:
                              Text('No enquiries yet. Pull down to refresh.')),
                    ),
                  for (final item in _items) _requestCard(item, hallScoped),
                ],
              ),
            ),
    );
  }
}
