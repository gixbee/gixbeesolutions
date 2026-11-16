import 'package:flutter/material.dart';

import '../../repositories/events_repository.dart';
import 'event_plan_create_screen.dart';

/// Hall customer review from the reference HTML: shows the exact selected slot,
/// price and advance terms before an enquiry is submitted. No payment occurs here.
class HallBookingReviewScreen extends StatefulWidget {
  const HallBookingReviewScreen({
    super.key,
    required this.hall,
    required this.selection,
    required this.eventType,
    required this.eventDate,
    required this.guests,
  });

  final Map<String, dynamic> hall;
  final EventServiceSelection selection;
  final String eventType;
  final DateTime eventDate;
  final int guests;

  @override
  State<HallBookingReviewScreen> createState() =>
      _HallBookingReviewScreenState();
}

class _HallBookingReviewScreenState extends State<HallBookingReviewScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  bool _acknowledged = false;

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
              Text(heading,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: _navy)),
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

  void _continue() {
    if (!_acknowledged || _rent <= 0) return;
    Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => EventPlanCreateScreen(
            eventType: widget.eventType,
            date: widget.eventDate,
            guests: widget.guests,
            services: const ['HALL'],
            selection: widget.selection,
          ),
        ));
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
                Text(eventMoney(_rent),
                    style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w900,
                        fontSize: 23)),
                const SizedBox(height: 5),
                const Text(
                    'Slot rent according to the current hall listing. Review the quote before confirming.'),
              ]),
              icon: Icons.currency_rupee),
          _card(
              'Advance payment — paid directly to hall',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eventMoney(_advance),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        color: Color(0xFFB91C1C))),
                const SizedBox(height: 5),
                const Text(
                    'Gixbee does not collect this payment. The owner must accept your request and issue a quote first.'),
                Text('Remaining balance: ${eventMoney(_rent - _advance)}'),
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
                onPressed: _acknowledged && _rent > 0 ? _continue : null,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue · Request to Book'),
              )),
        ),
      ])),
    );
  }
}
