import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import 'event_plan_detail_screen.dart';
import 'event_vendor_calendar_screen.dart';

class EventPlansScreen extends ConsumerStatefulWidget {
  const EventPlansScreen({
    super.key,
    this.business,
    this.bookingsOnly = false,
    this.interestService,
  });

  final Business? business;
  final bool bookingsOnly;
  final String? interestService;

  @override
  ConsumerState<EventPlansScreen> createState() => _EventPlansScreenState();
}

class _EventPlansScreenState extends ConsumerState<EventPlansScreen> {
  late Future<List<Map<String, dynamic>>> _plans;
  String _interestTab = 'active';

  @override
  void initState() {
    super.initState();
    _plans = _load();
  }

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(eventsRepositoryProvider).plans(businessId: widget.business?.id);

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _plans = next);
    try {
      await next;
    } catch (_) {
      // FutureBuilder shows the error.
    }
  }

  bool _isPast(Map<String, dynamic> plan) {
    if (plan['cancelledAt'] != null) return true;
    final end = DateTime.tryParse(plan['endTime']?.toString() ?? '');
    return end?.isBefore(DateTime.now()) ?? false;
  }

  String _interestStatus(Map<String, dynamic> plan) {
    if (plan['cancelledAt'] != null) return 'Cancelled';
    final completed = (plan['completedServices'] as num?)?.toInt() ?? 0;
    final confirmed = (plan['confirmedServices'] as num?)?.toInt() ?? 0;
    final offered = (plan['offeredServices'] as num?)?.toInt() ?? 0;
    if (completed > 0 && confirmed == completed) return 'Completed';
    if (confirmed > 0) return 'Booking confirmed';
    if (offered > 0) return 'Quote received — review now';
    return _isPast(plan) ? 'Event date passed' : 'Interest sent · awaiting vendor';
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final request = plan['serviceRequest'] as Map?;
    final customerInterest = widget.interestService != null;
    final label = request?['providerName']?.toString() ??
        plan['eventType']?.toString() ?? 'Event';
    final services = plan['services'] as List? ?? [];
    final status = customerInterest
        ? _interestStatus(plan)
        : plan['cancelledAt'] != null
            ? 'Cancelled'
            : widget.business == null
                ? '${plan['confirmedServices'] ?? 0}/${services.length} services confirmed'
                : plan['bookingStatus']?.toString().toLowerCase()
                      .replaceAll('_', ' ') ?? 'View enquiry and quotes';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: ListTile(
        contentPadding: const EdgeInsets.all(13),
        title: Text(label, style: const TextStyle(
            color: Color(0xFF1B2559), fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(eventDate(plan['startTime'])),
            Text('${plan['guestCount']} guests · ${plan['location']}'),
            const SizedBox(height: 6),
            Text(status, style: TextStyle(
              fontWeight: FontWeight.w800,
              color: status.contains('Quote received')
                  ? const Color(0xFF2563EB)
                  : status.contains('confirmed') || status == 'Completed'
                      ? const Color(0xFF047857)
                      : plan['cancelledAt'] != null ? Colors.red
                          : const Color(0xFFB45309),
            )),
          ]),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute<void>(
            builder: (_) => EventPlanDetailScreen(
              planId: plan['id'] as String,
              business: widget.business,
            ),
          ));
          if (mounted) await _refresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.bookingsOnly ? 'Booking register'
          : widget.interestService != null ? 'My interests'
          : widget.business == null ? 'My events' : 'Event enquiries'),
      actions: [
        if (widget.bookingsOnly && widget.business != null)
          IconButton(
            tooltip: 'Calendar bookings',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.push<void>(context,
              MaterialPageRoute(
                builder: (_) => EventVendorCalendarScreen(
                    businessId: widget.business!.id),
              ),
            ),
          ),
        IconButton(onPressed: _refresh,
            icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _plans,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: TextButton(
              onPressed: _refresh,
              child: Text('${eventError(snapshot.error!)} Retry')));
        }
        final all = (snapshot.data ?? []).where((plan) {
          if (widget.bookingsOnly) return plan['bookingStatus'] != null;
          if (widget.interestService != null) {
            return (plan['serviceRequest'] as Map?)?['kind'] ==
                widget.interestService;
          }
          return true;
        }).toList();
        final visible = widget.interestService == null ? all : all
            .where((plan) => _isPast(plan) == (_interestTab == 'past'))
            .toList();

        return Column(children: [
          if (widget.interestService != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Row(children: [
                for (final (value, name) in const [
                  ('active', 'Active'),
                  ('past', 'Past'),
                ])
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: SizedBox(width: double.infinity,
                        child: Text(name, textAlign: TextAlign.center)),
                      selected: _interestTab == value,
                      onSelected: (_) => setState(() => _interestTab = value),
                    ),
                  )),
              ]),
            ),
          Expanded(child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: visible.isEmpty
                  ? [
                      Padding(padding: const EdgeInsets.all(28),
                        child: Center(child: Text(widget.bookingsOnly
                          ? 'No bookings yet.'
                          : widget.interestService != null
                            ? 'No ${_interestTab == 'past' ? 'past' : 'active'} interests yet.'
                            : widget.business == null
                              ? 'Your published events will appear here.'
                              : 'No matching enquiries yet.'))),
                    ]
                  : visible.map(_planCard).toList(),
            ),
          )),
        ]);
      },
    ),
  );
}
