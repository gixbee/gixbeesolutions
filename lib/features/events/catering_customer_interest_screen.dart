import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'catering_customer_pricing.dart';
import 'event_plan_detail_screen.dart';

/// Final interest review: owner prices are estimates until a Rust-generated
/// quote is offered. This screen does not collect money or confirm a booking.
class CateringCustomerInterestScreen extends ConsumerStatefulWidget {
  const CateringCustomerInterestScreen({
    super.key,
    required this.vendorName,
    required this.businessId,
    required this.cityId,
    required this.eventType,
    required this.location,
    required this.day,
    required this.guests,
    required this.items,
    this.customize = false,
  });

  final String vendorName;
  final String businessId;
  final String cityId;
  final String eventType;
  final String location;
  final DateTime day;
  final int guests;
  final List<Map<String, dynamic>> items;
  final bool customize;

  @override
  ConsumerState<CateringCustomerInterestScreen> createState() =>
      _CateringCustomerInterestScreenState();
}

class _CateringCustomerInterestScreenState
    extends ConsumerState<CateringCustomerInterestScreen> {
  final _venue = TextEditingController();
  final _notes = TextEditingController();
  final _requestId = const Uuid().v4();
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 14, minute: 0);
  String _servingStyle = 'As offered';
  bool _sending = false;
  bool _acknowledged = false;

  @override
  void initState() {
    super.initState();
    _venue.text = widget.location;
  }

  @override
  void dispose() {
    _venue.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final time = await showTimePicker(
      context: context, initialTime: start ? _start : _end);
    if (time != null && mounted) {
      setState(() {
        if (start) { _start = time; } else { _end = time; }
      });
    }
  }

  DateTime _at(TimeOfDay time) => DateTime(
    widget.day.year, widget.day.month, widget.day.day,
    time.hour, time.minute);

  Future<void> _send() async {
    if (_sending || !_acknowledged) return;
    final estimate = CateringCustomerPrice.estimate(widget.items, widget.guests);
    if (estimate == null || estimate <= 0) {
      showGxSnack(context, 'Selected pricing is no longer valid. Review the menu.');
      return;
    }
    final start = _at(_start);
    final end = _at(_end);
    if (!start.isAfter(DateTime.now()) ||
        !end.isAfter(start) ||
        _venue.text.trim().isEmpty ||
        _venue.text.trim().length > 2000) {
      showGxSnack(context, 'Choose future event times and enter the venue or area.');
      return;
    }
    setState(() => _sending = true);
    try {
      final plan = await ref.read(eventsRepositoryProvider).create({
        'eventType': widget.eventType,
        'startTime': start.toUtc().toIso8601String(),
        'endTime': end.toUtc().toIso8601String(),
        'guestCount': widget.guests,
        'location': _venue.text.trim(),
        'notes': _notes.text.trim(),
        'cityId': widget.cityId,
        'services': const ['CATERING'],
        'targetBusinessId': widget.businessId,
        'clientRequestId': _requestId,
        'serviceRequest': {
          'itemIds': widget.items.map((item) => item['id']).toList(),
          'expectedEstimate': estimate,
          if (widget.customize && (_notes.text.trim().isNotEmpty ||
              _servingStyle != 'As offered'))
            'customization': {
              'servingStyle': _servingStyle,
              'dietaryNeeds': '',
              'menuChanges': _notes.text.trim(),
            },
        },
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) =>
            EventPlanDetailScreen(planId: plan['id'] as String)));
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _line(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.blueGrey))),
      Flexible(child: Text(value, textAlign: TextAlign.right,
        style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final estimate = CateringCustomerPrice.estimate(widget.items, widget.guests);
    final format = NumberFormat.decimalPattern('en_IN');
    String money(int value) => '₹${format.format(value)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Send Interest')),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(
          padding: const EdgeInsets.all(16), children: [
          Card(
            color: const Color(0xFFF0FDF4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.vendorName,
                    style: const TextStyle(fontSize: 17,
                      color: Color(0xFF14532D), fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(widget.items.length == 1 &&
                      widget.items.first['kind'] == 'PACKAGE'
                        ? 'Selected catering package'
                        : '${widget.items.length} individual dishes selected'),
                  const Divider(),
                  for (final item in widget.items)
                    Builder(builder: (context) {
                      final p = CateringCustomerPrice.forItem(item, widget.guests);
                      return _line(item['name']?.toString() ?? 'Dish',
                        p == null ? 'Unavailable' :
                        '${money(p.offerPerPlate)} × ${widget.guests} = ${money(p.total)}');
                    }),
                  const Divider(),
                  _line('Estimated total',
                    estimate == null ? 'Unavailable' : money(estimate), bold: true),
                  const Text('These are catalogue prices, not a confirmed quote.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF166534))),
                ]),
            ),
          ),
          const SizedBox(height: 12),
          _line('Event date', DateFormat('EEE, dd MMM yyyy').format(widget.day)),
          _line('Number of guests', '${widget.guests}'),
          TextField(
            controller: _venue,
            maxLength: 2000,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Event venue / area *',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _sending ? null : () => _pickTime(true),
              icon: const Icon(Icons.schedule),
              label: Text('Starts ${_start.format(context)}'),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: _sending ? null : () => _pickTime(false),
              icon: const Icon(Icons.schedule),
              label: Text('Ends ${_end.format(context)}'),
            )),
          ]),
          const SizedBox(height: 10),
          if (widget.customize) ...[
            DropdownButtonFormField<String>(
              initialValue: _servingStyle,
              decoration: const InputDecoration(
                  labelText: 'Preferred serving style',
                  border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(
                    value: 'As offered', child: Text('As offered')),
                DropdownMenuItem(
                    value: 'Buffet Service', child: Text('Buffet Service')),
                DropdownMenuItem(
                    value: 'Traditional Table Service',
                    child: Text('Traditional Table Service')),
                DropdownMenuItem(value: 'Both', child: Text('Both')),
              ],
              onChanged: _sending ? null :
                (v) => setState(() => _servingStyle = v ?? _servingStyle),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _notes,
            maxLength: 500,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Additional requirements (optional)',
              hintText: 'Live counters, special menu, service time or quantities',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _acknowledged,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I understand this is an enquiry, not a booking.'),
            subtitle: const Text('The caterer confirms availability and the final quote. '
                'Payments are arranged directly with the caterer.'),
            onChanged: _sending ? null :
              (value) => setState(() => _acknowledged = value ?? false),
          ),
        ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(width: double.infinity, child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _sending || !_acknowledged || estimate == null
                ? null : _send,
            icon: _sending
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
            label: Text(_sending ? 'Sending...' : 'Send Interest'),
          )),
        ),
      ])),
    );
  }
}
