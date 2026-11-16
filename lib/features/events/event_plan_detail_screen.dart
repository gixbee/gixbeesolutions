import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import '../business/business_unit_dashboard.dart';

class EventPlanDetailScreen extends ConsumerStatefulWidget {
  const EventPlanDetailScreen({super.key, required this.planId, this.business});
  final String planId;
  final Business? business;
  @override
  ConsumerState<EventPlanDetailScreen> createState() => _EventPlanDetailScreenState();
}

class _EventPlanDetailScreenState extends ConsumerState<EventPlanDetailScreen> {
  Map<String, dynamic>? _plan;
  String? _error;
  bool _busy = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    try {
      final plan = await ref.read(eventsRepositoryProvider).detail(widget.planId);
      if (mounted) setState(() { _plan = plan; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = eventError(e));
    }
  }

  Future<void> _mutate(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
      await _refresh();
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e));
      await _refresh();
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(title), content: SingleChildScrollView(child: Text(message)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))],
      )) ?? false;

  Future<void> _action(Map<String, dynamic> quote, String action, String title, String message) async {
    if (_busy || !await _confirm(title, message) || !mounted) return;
    await _mutate(() => ref.read(eventsRepositoryProvider).action(quote['id'] as String, action,
      {'updatedAt': quote['updatedAt']}));
  }

  Future<void> _offer(String service, {Map<Object?, Object?>? hallEnquiry}) async {
    final business = widget.business;
    if (_busy || business == null) return;
    final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(
      builder: (_) => _QuoteForm(service: service, request: _plan?['serviceRequest'] as Map?)));
    if (result == null || !mounted) return;
    await _mutate(() => ref.read(eventsRepositoryProvider).offer(widget.planId, {
      ...result,
      'businessId': business.id,
      'serviceType': service,
      if (hallEnquiry != null) ...{
        'hallEnquiryId': hallEnquiry['id'],
        'hallId': hallEnquiry['assignedHallId'],
      },
    }));
  }

  Future<void> _requestCancellation(Map<String, dynamic> quote) async {
    final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(
      builder: (_) => _CancellationForm(total: num.tryParse('${quote['amount']}') ?? 0)));
    if (result == null || !mounted) return;
    await _mutate(() => ref.read(eventsRepositoryProvider).action(quote['id'] as String,
      'request-cancel', {...result, 'updatedAt': quote['updatedAt']}));
  }

  Widget _button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(top: 10), child: GxButton(label: label,
      filled: false, accent: GixbeeTheme.accentPink, onTap: _busy ? null : action));

  Widget _quote(Map<String, dynamic> quote, bool customer) {
    final status = quote['status'] as String;
    final offered = status == 'OFFERED' && quote['expired'] != true;
    final requestedByMe = quote['cancellationRequestedByMe'] == true;
    final myPayment = quote[customer ? 'customerPaidAt' : 'vendorReceivedAt'] != null;
    final myCompletion = quote[customer ? 'customerCompletedAt' : 'vendorCompletedAt'] != null;
    final myRefund = quote[customer ? 'customerRefundReceivedAt' : 'vendorRefundSentAt'] != null;
    final label = eventServices[quote['serviceType']] ?? quote['serviceType'];
    final price = eventMoney(quote['amount']);
    const labels = {'OFFERED': 'Quote available', 'DECLINED': 'Declined / withdrawn',
      'EXPIRED': 'Expired', 'CONFIRMED': 'Confirmed', 'COMPLETED': 'Completed',
      'CANCEL_REQUESTED': 'Cancellation awaiting agreement', 'CANCELLED': 'Cancelled'};
    return Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(
      padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label · ${quote['businessName']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('$price total', style: TextStyle(fontSize: 21, color: context.gx.ink, fontWeight: FontWeight.w800)),
        Text(quote['expired'] == true ? 'Quote expired' : labels[status] ?? status),
        if (offered) Text('Valid until ${eventDate(quote['expiresAt'])}'),
        const SizedBox(height: 12),
        const Text('Included', style: TextStyle(fontWeight: FontWeight.w700)),
        Text('${quote['inclusions']}'),
        const SizedBox(height: 10),
        const Text('Cancellation terms', style: TextStyle(fontWeight: FontWeight.w700)),
        Text('${quote['cancellationTerms']}'),
        if (customer && quote['vendorPhone'] != null) ...[
          const SizedBox(height: 12), SelectableText('Vendor contact: ${quote['vendorPhone']}'),
        ],
        if (offered) ...[
          if (customer) _button('Accept quote · $price', () => _action(quote, 'accept', 'Confirm this vendor?',
            '$label from ${quote['businessName']}\nTotal: $price\n\nIncluded: ${quote['inclusions']}\n\nCancellation: ${quote['cancellationTerms']}\n\nThis confirms the service for your event schedule. Arrange payment directly with the vendor.')),
          _button(customer ? 'Decline quote' : 'Withdraw quote', () => _action(quote, 'decline',
            customer ? 'Decline this quote?' : 'Withdraw this quote?', 'This quote will no longer be available for confirmation.')),
        ],
        if (status == 'CONFIRMED' || status == 'COMPLETED') ...[
          const Divider(height: 28),
          const Text('Direct payment', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Customer: ${quote['customerPaidAt'] == null ? 'payment not acknowledged' : 'marked paid'}'),
          Text('Vendor: ${quote['vendorReceivedAt'] == null ? 'receipt not acknowledged' : 'confirmed receipt'}'),
          const SizedBox(height: 10),
          Text('Service completed: customer ${quote['customerCompletedAt'] == null ? 'pending' : 'confirmed'}, '
            'vendor ${quote['vendorCompletedAt'] == null ? 'pending' : 'confirmed'}'),
          if (status == 'CONFIRMED') ...[
            if (!myPayment) _button(customer ? 'I paid the full amount' : 'I received the full amount',
              () => _action(quote, 'payment', 'Confirm direct payment?',
                customer ? 'Confirm only after you have paid $price directly to the vendor. This button records your acknowledgement; it does not transfer money.'
                  : 'Confirm only after you have received $price from the customer. This records your acknowledgement.')),
            if (!myCompletion && !(DateTime.tryParse('${_plan!['startTime']}')?.isAfter(DateTime.now()) ?? true))
              _button('Confirm service completed', () => _action(quote, 'complete', 'Service completed?',
                'Confirm that the agreed $label service has been delivered. The booking closes when both parties confirm service completion and full payment.')),
            _button('Request cancellation', () => _requestCancellation(quote)),
          ],
        ],
        if (status == 'CANCEL_REQUESTED' || status == 'CANCELLED') ...[
          const Divider(height: 28),
          Text('Reason: ${quote['cancellationReason']}'),
          Text('Proposed refund: ${eventMoney(quote['cancellationRefund'])}'),
          if (status == 'CANCEL_REQUESTED') ...[
            Text(requestedByMe ? 'Waiting for the other participant. The booking remains reserved.'
              : 'Review the proposal. The booking remains reserved until cancellation is accepted.'),
            if (!requestedByMe) ...[
              _button('Accept cancellation', () => _action(quote, 'accept-cancel', 'Accept cancellation?',
                'The service will be cancelled. Agreed refund: ${eventMoney(quote['cancellationRefund'])}, paid directly by the vendor to the customer.')),
              _button('Keep booking confirmed', () => _action(quote, 'reject-cancel', 'Reject cancellation proposal?',
                'The booking returns to confirmed. Contact the other participant to agree on the next step.')),
            ],
          ],
          if (status == 'CANCELLED' && (num.tryParse('${quote['cancellationRefund']}') ?? 0) > 0) ...[
            Text('Refund sent: ${quote['vendorRefundSentAt'] == null ? 'pending' : 'acknowledged'}'),
            Text('Refund received: ${quote['customerRefundReceivedAt'] == null ? 'pending' : 'acknowledged'}'),
            if (!myRefund) _button(customer ? 'I received the refund' : 'I sent the refund',
              () => _action(quote, 'refund', 'Confirm refund?',
                'Confirm only after ${customer ? 'receiving' : 'sending'} ${eventMoney(quote['cancellationRefund'])} directly. This button does not transfer money.')),
          ],
        ],
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final customer = plan?['isCustomer'] == true;
    final quotes = (plan?['quotes'] as List? ?? []).map((q) => Map<String, dynamic>.from(q as Map))
      .where((q) => customer || widget.business == null || q['businessId'] == widget.business!.id).toList();
    final services = (plan?['services'] as List? ?? []).map((s) => s.toString()).toList();
    final request = plan?['serviceRequest'] as Map?;
    final active = plan != null && plan['cancelledAt'] == null &&
      (DateTime.tryParse('${plan['startTime']}')?.isAfter(DateTime.now()) ?? false);
    final business = widget.business;
    final supported = {...?business?.eventServices, if (business?.serviceType != null) business!.serviceType!};
    final hallEnquiry = (plan?['hallEnquiries'] as List? ?? [])
        .whereType<Map>()
        .where((item) => item['businessId'] == business?.id)
        .firstOrNull;
    final canQuoteHall = hallEnquiry == null ||
        (hallEnquiry['assignedHallId'] != null &&
            const ['ASSIGNED', 'QUOTE_OFFERED'].contains(hallEnquiry['status']));
    final hallStart = hallEnquiry?['proposedStartAt'];
    final hallEnd = hallEnquiry?['proposedEndAt'];
    final hallName = hallEnquiry?['hallName'];
    return Scaffold(
      appBar: AppBar(title: Text(plan?['eventType']?.toString() ?? 'Event'),
        actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
      body: plan == null ? Center(child: _error == null ? const CircularProgressIndicator()
        : Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _refresh, child: const Text('Try again'))]))
        : RefreshIndicator(onRefresh: _refresh, child: ListView(padding: const EdgeInsets.all(20), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!)),
          Text('${eventDate(plan['startTime'])} – ${eventDate(plan['endTime'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${plan['guestCount']} guests · ${plan['location']}'),
          if (request != null) ...[
            const SizedBox(height: 12),
            if (request['providerName'] case final String name) Text(name),
            if (request['kind'] == 'HALL')
              Text('${request['hallName']} · ${request['slot']} · ${request['withAc'] == true ? 'With AC' : 'Without AC'}')
            else
              for (final line in (request['items'] as List? ?? []).whereType<Map>())
                Text('${line['item']['name']} · ${eventMoney(line['unitPrice'])}${request['kind'] == 'CATERING' ? ' / plate' : ''}'),
            Text('Requested estimate ${eventMoney(request['estimate'])}'),
          ],
          if (plan['cancelledAt'] != null) const Text('Event cancelled'),
          if ('${plan['notes'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('${plan['notes']}')),
          if (!customer && plan['customerContact'] is Map) ...[
            const SizedBox(height: 12),
            SelectableText('Customer: ${plan['customerContact']['name'] ?? ''}\n${plan['customerContact']['phoneNumber'] ?? ''}'),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, children: services.map((s) => Chip(label: Text(eventServices[s] ?? s))).toList()),
          if (customer) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(
            '${quotes.where((q) => ['CONFIRMED', 'COMPLETED'].contains(q['status'])).length}/${services.length} services confirmed. '
            'Each service has its own vendor, price and cancellation terms.')),
          if (!customer && business != null && active) ...[
            if (hallStart != null && hallEnd != null)
              Text('Assigned hall slot: ${eventDate(hallStart)} – ${eventDate(hallEnd)}'),
            const SizedBox(height: 12), const Text('Send or update a quote', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            for (final service in services.where(supported.contains))
              if (!quotes.any((q) => q['serviceType'] == service && ['CONFIRMED', 'COMPLETED', 'CANCEL_REQUESTED', 'CANCELLED'].contains(q['status'])))
                if (service == 'HALL' && !canQuoteHall)
                  const Text('Open Hall enquiries to review and assign a hall before quoting.')
                else
                  _button(
                    service == 'HALL' && hallName is String
                        ? 'Quote for $hallName'
                        : 'Quote for ${eventServices[service] ?? service}',
                    () => _offer(service, hallEnquiry: service == 'HALL' ? hallEnquiry : null),
                  ),
          ],
          if (!customer && business == null && active)
            _button('Open my business to send a quote', () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const BusinessUnitDashboard()))),
          const SizedBox(height: 20),
          Text(customer ? 'Vendor quotes and bookings' : 'Your quotes and bookings', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (quotes.isEmpty) const Text('No quotes yet. Matching businesses can review the enquiry and send their price and terms.'),
          ...quotes.map((q) => _quote(q, customer)),
          if (customer && plan['cancelledAt'] == null && !quotes.any((q) => ['CONFIRMED', 'COMPLETED', 'CANCEL_REQUESTED'].contains(q['status'])))
            _button('Cancel event enquiry', () async {
              if (await _confirm('Cancel this event enquiry?', 'Open quotes will be closed. Previously agreed refunds remain recorded.') && mounted) {
                await _mutate(() => ref.read(eventsRepositoryProvider).cancel(widget.planId));
              }
            }),
        ])),
    );
  }
}

class _QuoteForm extends StatefulWidget {
  const _QuoteForm({required this.service, this.request});
  final String service;
  final Map? request;
  @override
  State<_QuoteForm> createState() => _QuoteFormState();
}

class _QuoteFormState extends State<_QuoteForm> {
  final _key = GlobalKey<FormState>();
  late final _price = TextEditingController(text: widget.request?['estimate']?.toString() ?? '');
  late final _scope = TextEditingController(text: widget.service == 'HALL'
      ? (widget.request?['hallName']?.toString() ?? '')
      : ((widget.request?['items'] as List?) ?? []).whereType<Map>()
          .map((line) => line['item']['name']).join(', '));
  final _terms = TextEditingController();
  @override
  void dispose() { _price.dispose(); _scope.dispose(); _terms.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Quote · ${eventServices[widget.service]}')),
    body: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Quote for the full event schedule and guest count. Include all applicable charges. Quotes expire after 24 hours or when the event starts, whichever is earlier. Updating replaces your previous open quote.'),
      const SizedBox(height: 20),
      GxTextField(controller: _price, label: 'Total price (₹)', keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 || n > 999999999 ? 'Enter a valid positive total' : null; }),
      const SizedBox(height: 16),
      GxTextField(controller: _scope, label: 'Everything included', maxLines: 5, maxLength: 5000,
        validator: (v) => v == null || v.trim().isEmpty ? 'Describe the service, capacity and inclusions' : null),
      const SizedBox(height: 16),
      GxTextField(controller: _terms, label: 'Payment and cancellation terms', maxLines: 5, maxLength: 5000,
        hint: 'Payment timing, cancellation deadlines and refund conditions',
        validator: (v) => v == null || v.trim().isEmpty ? 'Provide payment and cancellation terms' : null),
      const SizedBox(height: 24),
      GxButton(label: 'Send quote', onTap: () {
        if (_key.currentState!.validate()) Navigator.pop(context, <String, dynamic>{
          'amount': double.parse(_price.text), 'inclusions': _scope.text.trim(), 'cancellationTerms': _terms.text.trim()});
      }),
    ])),
  );
}

class _CancellationForm extends StatefulWidget {
  const _CancellationForm({required this.total});
  final num total;
  @override
  State<_CancellationForm> createState() => _CancellationFormState();
}

class _CancellationFormState extends State<_CancellationForm> {
  final _key = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _refund = TextEditingController(text: '0');
  @override
  void dispose() { _reason.dispose(); _refund.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Request cancellation')),
    body: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Use the agreed cancellation terms. The other participant must accept the proposal. The booking stays confirmed until agreement, and any refund is paid directly by the vendor.'),
      const SizedBox(height: 20),
      GxTextField(controller: _reason, label: 'Reason', maxLines: 4, maxLength: 2000,
        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a cancellation reason' : null),
      const SizedBox(height: 16),
      GxTextField(controller: _refund, label: 'Proposed refund to customer (₹)', keyboardType: const TextInputType.numberWithOptions(decimal: true),
        validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n < 0 || n > widget.total ? 'Enter a refund from ₹0 to ${eventMoney(widget.total)}' : null; }),
      const SizedBox(height: 24),
      GxButton(label: 'Send cancellation proposal', onTap: () {
        if (_key.currentState!.validate()) Navigator.pop(context, <String, dynamic>{
          'reason': _reason.text.trim(), 'refundAmount': double.parse(_refund.text)});
      }),
    ])),
  );
}
