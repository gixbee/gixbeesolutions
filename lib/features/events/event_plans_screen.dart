import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import 'event_plan_detail_screen.dart';
import 'event_vendor_calendar_screen.dart';

class EventPlansScreen extends ConsumerStatefulWidget {
  const EventPlansScreen({super.key, this.business, this.bookingsOnly = false, this.interestService});
  final Business? business;
  final bool bookingsOnly;
  final String? interestService;
  @override
  ConsumerState<EventPlansScreen> createState() => _EventPlansScreenState();
}

class _EventPlansScreenState extends ConsumerState<EventPlansScreen> {
  late Future<List<Map<String, dynamic>>> _plans;
  @override
  void initState() { super.initState(); _plans = _load(); }
  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(eventsRepositoryProvider).plans(businessId: widget.business?.id);
  Future<void> _refresh() async {
    final next = _load(); setState(() => _plans = next);
    try { await next; } catch (_) { /* FutureBuilder displays the error. */ }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.bookingsOnly ? 'Booking register'
        : widget.interestService != null ? 'My interests'
        : widget.business == null ? 'My events' : 'Event enquiries'),
      actions: [
        if (widget.bookingsOnly && widget.business != null)
          IconButton(
            tooltip: 'Calendar bookings',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
              builder: (_) => EventVendorCalendarScreen(businessId: widget.business!.id),
            )),
          ),
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ]),
    body: FutureBuilder<List<Map<String, dynamic>>>(future: _plans, builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [Text(eventError(snapshot.error!)),
        TextButton(onPressed: _refresh, child: const Text('Try again'))])));
      final plans = (snapshot.data ?? []).where((plan) {
        if (widget.bookingsOnly) return plan['bookingStatus'] != null;
        if (widget.interestService != null) {
          return (plan['serviceRequest'] as Map?)?['kind'] == widget.interestService;
        }
        return true;
      }).toList();
      return RefreshIndicator(onRefresh: _refresh, child: ListView(
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
        children: plans.isEmpty ? [Padding(padding: const EdgeInsets.all(24), child: Text(
          widget.bookingsOnly ? 'No bookings yet.' : widget.interestService != null
            ? 'Requests you send to a provider will appear here.'
            : widget.business == null ? 'Your published events will appear here.' : 'No matching enquiries yet.'))]
          : plans.map((p) => Card(child: ListTile(
            title: Text((p['serviceRequest'] as Map?)?['providerName']?.toString()
                ?? p['eventType']?.toString() ?? 'Event'),
            subtitle: Text('${eventDate(p['startTime'])}\n${p['guestCount']} guests · ${p['location']}\n'
              '${p['cancelledAt'] != null ? 'Cancelled' : widget.business == null ? '${p['confirmedServices'] ?? 0}/${(p['services'] as List).length} services confirmed' : p['bookingStatus']?.toString().toLowerCase().replaceAll('_', ' ') ?? 'View enquiry and quotes'}'),
            isThreeLine: true, trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                EventPlanDetailScreen(planId: p['id'] as String, business: widget.business)));
              if (mounted) await _refresh();
            },
          ))).toList(),
      ));
    }),
  );
}
