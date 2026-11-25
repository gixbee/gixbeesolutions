import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../repositories/cities_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_calendar.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../theme.dart';
import 'event_hold_screen.dart';

class EventPlanCreateScreen extends ConsumerStatefulWidget {
  const EventPlanCreateScreen(
      {super.key,
      required this.eventType,
      required this.date,
      required this.guests,
      required this.services,
      this.selection});
  final String eventType;
  final DateTime date;
  final int guests;
  final List<String> services;
  final EventServiceSelection? selection;

  @override
  ConsumerState<EventPlanCreateScreen> createState() =>
      _EventPlanCreateScreenState();
}

class _EventPlanCreateScreenState extends ConsumerState<EventPlanCreateScreen> {
  final _form = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  final _requestId = const Uuid().v4();
  late final TextEditingController _guests;
  late DateTime _start;
  late DateTime _end;
  String? _cityId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _guests = TextEditingController(text: '${widget.guests}');
    _start = widget.selection?.start ??
        DateTime(widget.date.year, widget.date.month, widget.date.day, 10);
    _end = widget.selection?.end ?? _start.add(const Duration(hours: 4));
    _cityId = widget.selection?.cityId ?? ref.read(currentCityProvider)?.id;
    _address.text = widget.selection?.address ?? '';
    _notes.text = widget.selection?.requirements ?? '';
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    _guests.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    final now = DateTime.now();
    final date = await showGxCalendar(context,
        title: start ? 'Start date' : 'End date',
        initialDate: current,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: now.add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (time == null || !mounted) return;
    setState(() {
      final selected =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (start) {
        _start = selected;
      } else {
        _end = selected;
      }
    });
  }

  Future<void> _publish() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_cityId == null) {
      showGxSnack(context, 'Select your event city');
      return;
    }
    if (!_start.isAfter(DateTime.now()) ||
        !_end.isAfter(_start) ||
        _end.difference(_start) > const Duration(days: 14)) {
      showGxSnack(
          context, 'Choose future start and end times, up to 14 days apart');
      return;
    }
    setState(() => _busy = true);
    try {
      final plan = await ref.read(eventsRepositoryProvider).create({
        'eventType': widget.eventType,
        'startTime': _start.toUtc().toIso8601String(),
        'endTime': _end.toUtc().toIso8601String(),
        'guestCount': int.parse(_guests.text),
        'location': _address.text.trim(),
        'notes': _notes.text.trim(),
        'cityId': _cityId,
        'services': widget.services,
        'clientRequestId': _requestId,
        if (widget.selection case final selection?) ...{
          'targetBusinessId': selection.businessId,
          'serviceRequest': selection.request,
        },
      });
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
              builder: (_) => EventHoldScreen(
                    planId: plan['id'] as String,
                    title: widget.eventType,
                  )));
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    final selection = widget.selection;
    final fixedSlot = selection?.start != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Review your event')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(widget.eventType,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: context.gx.ink)),
            const SizedBox(height: 12),
            Wrap(
                spacing: 8,
                children: widget.services
                    .map((s) => Chip(label: Text(eventServices[s] ?? s)))
                    .toList()),
            const SizedBox(height: 12),
            if (selection == null)
              const Text(
                  'Businesses in your city can send a total price, inclusions and cancellation terms for each service. Review and confirm each vendor separately. Payment is directly to the vendor.')
            else ...[
              Text(selection.summary),
              const Text(
                  'The provider will confirm availability and send a quote. Pay the provider directly after confirmation.'),
            ],
            const SizedBox(height: 16),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Starts'),
                subtitle: Text(eventDate(_start.toIso8601String())),
                onTap: _busy || fixedSlot ? null : () => _pickTime(true)),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available),
                title: const Text('Ends'),
                subtitle: Text(eventDate(_end.toIso8601String())),
                onTap: _busy || fixedSlot ? null : () => _pickTime(false)),
            const Text('Times are shown in your device timezone.'),
            const SizedBox(height: 16),
            if (selection == null)
              cities.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => TextButton(
                    onPressed: () => ref.invalidate(citiesProvider),
                    child: const Text('Reload cities')),
                data: (items) => items.isEmpty
                    ? TextButton(
                        onPressed: () => ref.invalidate(citiesProvider),
                        child: const Text('No event cities available. Reload'))
                    : DropdownButtonFormField<String>(
                        initialValue:
                            items.any((c) => c.id == _cityId) ? _cityId : null,
                        decoration:
                            const InputDecoration(labelText: 'Event city'),
                        items: items
                            .map((c) => DropdownMenuItem(
                                value: c.id, child: Text(c.displayName)))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _cityId = value),
                        validator: (value) =>
                            value == null ? 'Select a city' : null),
              ),
            const SizedBox(height: 16),
            if (selection != null)
              Text('${widget.guests} guests')
            else
              GxTextField(
                  controller: _guests,
                  label: 'Guests',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 100000
                        ? 'Enter 1–100,000 guests'
                        : null;
                  }),
            const SizedBox(height: 16),
            GxTextField(
                controller: _address,
                label: 'Venue or preferred area',
                maxLength: 2000,
                maxLines: 2,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter an address or preferred area'
                    : null),
            const SizedBox(height: 16),
            GxTextField(
                controller: _notes,
                label: 'Requirements for your vendors',
                hint:
                    'Food preferences, venue capacity, timing, style and access…',
                maxLines: 4,
                maxLength: 5000),
            const SizedBox(height: 12),
            Text(selection == null
                ? 'Your event details and requirements will be visible to matching verified businesses. Contact details are shared after confirmation.'
                : 'Only the selected provider receives this request. Contact details are shared after confirmation.'),
            const SizedBox(height: 24),
            GxButton(
                label: selection == null ? 'Publish enquiry' : 'Send request',
                loading: _busy,
                onTap: _publish,
                accent: GixbeeTheme.accentPink),
          ])),
    );
  }
}

class EventServiceSelection {
  const EventServiceSelection({
    required this.businessId,
    required this.cityId,
    required this.summary,
    required this.request,
    this.address,
    this.requirements,
    this.start,
    this.end,
  });

  final String businessId;
  final String cityId;
  final String summary;
  final Map<String, dynamic> request;
  final String? address;
  final String? requirements;
  final DateTime? start;
  final DateTime? end;
}
