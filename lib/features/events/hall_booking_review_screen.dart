import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'event_hold_screen.dart';
import 'event_plans_screen.dart';

import '../../repositories/events_repository.dart';
import 'event_plan_create_screen.dart';

/// Hall customer review from the reference HTML: shows the exact selected slot,
/// price and advance terms before an enquiry is submitted. No payment occurs here.
class HallBookingReviewScreen extends ConsumerStatefulWidget {
  const HallBookingReviewScreen({
    super.key,
    required this.hall,
    required this.selection,
    required this.eventType,
    required this.eventDate,
    required this.guests,
    this.slot,
  });

  final Map<String, dynamic> hall;
  final EventServiceSelection selection;
  final String eventType;
  final DateTime eventDate;
  final int guests;
  final Map<String,dynamic>? slot;

  @override
  ConsumerState<HallBookingReviewScreen> createState() =>
      _HallBookingReviewScreenState();
}

class _HallBookingReviewScreenState extends ConsumerState<HallBookingReviewScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  String _money(num value) => '₹${NumberFormat.decimalPattern('en_IN').format(value)}';
  bool _acknowledged = false;
  bool _sending = false;
  final _requestId = const Uuid().v4();
  final _area = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState(){
    super.initState();
    _area.text=widget.selection.address??widget.hall['location']?.toString()??'';
    _notes.text=widget.selection.requirements??'';
  }

  @override
  void dispose(){
    _area.dispose();
    _notes.dispose();
    super.dispose();
  }

  Map get _package => widget.hall['package'] as Map? ?? const {};
  Map get _payment => _package['payment'] as Map? ?? const {};
  int get _rent =>
      (widget.selection.request['expectedEstimate'] as num?)?.round() ?? 0;
  int get _advance {
    final raw = _payment['advanceType'] == 'percent'
        ? (_rent * (((_payment['advancePct'] as num?) ?? 0) / 100)).round()
        : ((_payment['advanceFixed'] as num?) ?? 0).round();
    return raw.clamp(0, _rent).toInt();
  }

  String get _slotLabel {
    final label = widget.selection.summary.split('\n').first;
    return label.isEmpty ? 'Hall slot' : label;
  }

  Widget _card(String heading, Widget body, {IconData? icon}) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: _navy),
                const SizedBox(width: 7)
              ],
              Expanded(child:Text(heading,
                  softWrap:true,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: _navy))),
            ]),
            const SizedBox(height: 10),
            body,
          ]),
        ),
      );

  Widget _policy(String key, String title) {
    final rules =
        (_package[key] as List? ?? const []).whereType<Map>().toList();
    if (rules.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      children: [
        for (final row in rules)
          ListTile(
            dense: true,
            title: Text(
                '${row['minDaysBeforeEvent'] ?? 0}–${row['maxDaysBeforeEvent'] ?? 'more'} days before event'),
            subtitle: Text(
                '${row['deductionPercent'] ?? 0}% deduction of ${_package['deductionBasis'] == 'TOTAL_QUOTE' ? 'the total quote' : 'the advance'}'),
          ),
      ],
    );
  }

  Future<void> _continue() async {
    if (!_acknowledged || _sending || _rent < 0) return;
    final from=widget.selection.start, to=widget.selection.end;
    final venue=_area.text.trim();
    if(from==null || to==null || !from.isAfter(DateTime.now()) ||
       !to.isAfter(from) ||
       to.difference(from)>const Duration(days:14) ||
       venue.isEmpty || venue.length>2000 ||
       _notes.text.length>5000) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Choose a future slot, valid venue and request notes.')));
      return;
    }
    setState(()=>_sending=true);
    try {
      final response=await ref.read(eventsRepositoryProvider).create({
        'clientRequestId':_requestId,
        'targetBusinessId':widget.selection.businessId,
        'cityId':widget.selection.cityId,
        'eventType':widget.eventType,
        'guestCount':widget.guests,
        'location':venue,
        'notes':_notes.text.trim(),
        'startTime':from.toUtc().toIso8601String(),
        'endTime':to.toUtc().toIso8601String(),
        'services':const ['HALL'],
        'serviceRequest':widget.selection.request,
      });
      if(!mounted)return;
      final id=response['id'] as String;
      Navigator.of(context).pushReplacement<void,void>(
        MaterialPageRoute(builder:(_)=>_HallRequestSentScreen(planId:id)));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(eventError(e))));
    } finally {
      if(mounted)setState(()=>_sending=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hallName = widget.hall['hallName']?.toString() ?? 'Hall';
    final business = widget.hall['businessName']?.toString() ?? '';
    final dueDays = (_payment['fullDueDays'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          _card(
              'Selected venue',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hallName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                if (business.isNotEmpty) Text(business),
                Text(widget.hall['location']?.toString() ?? ''),
                const SizedBox(height: 8),
                Text(_slotLabel),
              ]),
              icon: Icons.apartment),
          _card(
              'Event Details',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Event: ${widget.eventType}'),
                Text('Guests: ${widget.guests}'),
                if (widget.selection.start != null)
                  Text(
                      'From: ${eventDate(widget.selection.start!.toIso8601String())}'),
                if (widget.selection.end != null)
                  Text(
                      'To: ${eventDate(widget.selection.end!.toIso8601String())}'),
                Text(widget.selection.request['withAc'] == true
                    ? 'With AC'
                    : 'Without AC'),
              ]),
              icon: Icons.event_available),
          _card(
              'Hall Charge',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_money(_rent),
                    style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 23)),
                if(widget.slot?['basePrice'] is num &&
                    (widget.slot!['basePrice'] as num)>_rent)
                  Text(_money(widget.slot!['basePrice'] as num),
                    style:const TextStyle(
                      color:Colors.blueGrey,
                      decoration:TextDecoration.lineThrough)),
                if(widget.slot?['discountPercent'] is num &&
                    (widget.slot!['discountPercent'] as num)>0)
                  Text('${widget.slot!['discountPercent']}% OFF',
                    style:const TextStyle(color:_green,
                      fontWeight:FontWeight.w800)),
                const SizedBox(height: 5),
                const Text(
                    'Slot rent according to the current hall listing. Review the quote before confirming.'),
              ]),
              icon: Icons.currency_rupee),
          _card(
              'Advance payment — paid directly to hall',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_money(_advance),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Color(0xFFB91C1C))),
                const SizedBox(height: 5),
                const Text(
                    'Gixbee does not collect this payment. The owner must accept your request and issue a quote first.'),
                Text('Remaining balance: ${_money(_rent - _advance)}'),
                if (dueDays > 0)
                  Text('Full payment due $dueDays days before the event.'),
              ]),
              icon: Icons.payments_outlined),
          _card(
              'Booking and cancellation policies',
              Column(children: [
                _policy('cancelRules', 'Cancellation Policy'),
                _policy('rescheduleRules', 'Rescheduling Policy'),
              ]),
              icon: Icons.policy_outlined),
          _card('Venue / Area',
            Column(children:[
              TextField(controller:_area,maxLength:2000,
                maxLines:2,decoration:const InputDecoration(
                  labelText:'Event venue / area *',
                  border:OutlineInputBorder())),
              const SizedBox(height:9),
              TextField(controller:_notes,maxLength:5000,maxLines:3,
                decoration:const InputDecoration(
                  labelText:'Additional booking requests',
                  border:OutlineInputBorder())),
            ]),icon:Icons.location_on_outlined),
          _card(
              'How booking works',
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Send a request to the hall owner'),
                    SizedBox(height: 6),
                    Text('2. Owner reviews availability and sends a quote'),
                    SizedBox(height: 6),
                    Text(
                        '3. Accept the quote and arrange advance payment directly'),
                    SizedBox(height: 6),
                    Text('4. Both parties acknowledge payment and completion'),
                  ]),
              icon: Icons.timeline),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _acknowledged,
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
                'I understand this sends a booking request, not a confirmed reservation.'),
            subtitle: const Text(
                'Availability and final terms are confirmed by the hall owner.'),
          ),
        ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                onPressed: _acknowledged && _rent >= 0 && !_sending ?
                    _continue : null,
                icon: const Icon(Icons.send_outlined),
                label: Text(_sending?'Sending request...':'Request to Book'),
              )),
        ),
      ])),
    );
  }
}

class _HallRequestSentScreen extends StatelessWidget {
  const _HallRequestSentScreen({required this.planId});
  final String planId;

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Request Sent')),
    body:SafeArea(child:ListView(
      padding:const EdgeInsets.all(20),children:[
        const SizedBox(height:28),
        const Icon(Icons.check_circle_rounded,size:70,
          color:Color(0xFF12B76A)),
        const SizedBox(height:14),
        const Text('Your Hall Request Has Been Sent!',
          textAlign:TextAlign.center,
          style:TextStyle(color:Color(0xFF1B2559),
            fontSize:21,fontWeight:FontWeight.w900)),
        const SizedBox(height:10),
        const Text('The owner will review the slot and may issue a quote. '
          'No hall is booked or paid for yet.',
          textAlign:TextAlign.center,
          style:TextStyle(color:Colors.blueGrey)),
        const SizedBox(height:20),
        for(final (done,title,subtitle) in const [
          (true,'Request submitted','Hall owner notified'),
          (false,'Owner review','Waiting for acceptance and hall assignment'),
          (false,'Quote & advance','Confirm terms and pay the venue directly'),
          (false,'Booking confirmed','Confirmed only after required acknowledgements'),
        ])
          ListTile(
            leading:Icon(done?Icons.check_circle:Icons.circle_outlined,
              color:done?const Color(0xFF12B76A):Colors.blueGrey),
            title:Text(title),subtitle:Text(subtitle)),
        const SizedBox(height:18),
        FilledButton(
          onPressed:()=>Navigator.pushReplacement(context,
            MaterialPageRoute<void>(builder:(_)=>
              EventHoldScreen(planId:planId, title:'Hall request'))),
          child:const Text('View Request Details')),
        const SizedBox(height:8),
        OutlinedButton(
          onPressed:()=>Navigator.pushReplacement(context,
            MaterialPageRoute<void>(builder:(_)=>
              const EventPlansScreen(interestService:'HALL'))),
          child:const Text('My Events')),
      ])),
  );
}
