import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../shared/widgets/gx_empty.dart';
import '../../shared/widgets/gx_snackbar.dart';

class EventVendorCalendarScreen extends ConsumerStatefulWidget {
  const EventVendorCalendarScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<EventVendorCalendarScreen> createState() =>
      _EventVendorCalendarScreenState();
}

class _EventVendorCalendarScreenState
    extends ConsumerState<EventVendorCalendarScreen> {
  late Future<List<Map<String, dynamic>>> _entries = _load();
  bool _saving = false;

  Future<List<Map<String, dynamic>>> _load() =>
      ref.read(eventsRepositoryProvider).vendorCalendar(widget.businessId);

  Future<void> _add() async {
    final draft = await Navigator.of(context).push<_CalendarDraft>(
      MaterialPageRoute(builder: (_) => const _NewCalendarBooking()),
    );
    if (!mounted || draft == null) return;
    await _save(() => ref.read(eventsRepositoryProvider).addCalendarBooking(
          widget.businessId,
          draft.title,
          draft.start,
          draft.end,
        ));
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    if (_saving || item['cancelledAt'] != null) return;
    final draft = await Navigator.of(context).push<_CalendarDraft>(
      MaterialPageRoute(builder: (_) => _NewCalendarBooking(existing: item)),
    );
    if (!mounted || draft == null) return;
    await _save(() => ref.read(eventsRepositoryProvider).updateCalendarBooking(
      widget.businessId, item['id'] as String,
      draft.title, draft.start, draft.end,
    ));
  }

  Future<void> _save(Future<void> Function() submit) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await submit();
      if (mounted) setState(() => _entries = _load());
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calendar bookings')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _entries,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return GxNetworkError(
                error: snapshot.error,
                title: 'Calendar bookings unavailable',
                onRetry: () => setState(() => _entries = _load()),
              );
            }
            final entries = snapshot.data ?? [];
            return ListView(padding: const EdgeInsets.all(16), children: [
              GxButton(
                  label: 'Add outside booking', onTap: _saving ? null : _add),
              if (entries.isEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: GxEmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No outside bookings',
                      message: 'Bookings added to your calendar will appear here.',
                    )),
              for (final entry in entries)
                Card(
                    child: ListTile(
                  title: Text(entry['title']?.toString() ?? 'Booking'),
                  subtitle: Text(
                      '${eventDate(entry['startAt'])} – ${eventDate(entry['endAt'])}'
                      '${entry['cancelledAt'] == null ? '' : '\nCancelled'}'),
                  onTap: entry['cancelledAt'] == null &&
                      (DateTime.tryParse('${entry['endAt']}')
                              ?.isAfter(DateTime.now()) ?? false)
                    ? () => _edit(entry) : null,
                  trailing: entry['cancelledAt'] == null &&
                          (DateTime.tryParse('${entry['endAt']}')
                                  ?.isAfter(DateTime.now()) ??
                              false)
                      ? TextButton(
                          onPressed: _saving
                              ? null
                              : () => _save(() => ref
                                  .read(eventsRepositoryProvider)
                                  .cancelCalendarBooking(
                                    widget.businessId,
                                    entry['id'] as String,
                                  )),
                          child: const Text('Release time'),
                        )
                      : null,
                )),
            ]);
          },
        ),
      );
}

typedef _CalendarDraft = ({String title, DateTime start, DateTime end});

class _NewCalendarBooking extends StatefulWidget {
  const _NewCalendarBooking({this.existing});
  final Map<String, dynamic>? existing;

  @override
  State<_NewCalendarBooking> createState() => _NewCalendarBookingState();
}

class _NewCalendarBookingState extends State<_NewCalendarBooking> {
  final _title = TextEditingController();
  late DateTime _start = DateTime.now().add(const Duration(days: 1));
  late DateTime _end = _start.add(const Duration(hours: 2));

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    if (item != null) {
      _title.text = item['title']?.toString() ?? '';
      _start = DateTime.tryParse(item['startAt']?.toString() ?? '')
          ?.toLocal() ?? _start;
      _end = DateTime.tryParse(item['endAt']?.toString() ?? '')
          ?.toLocal() ?? _end;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final previous = start ? _start : _end;
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
        context: context,
        initialDate: previous,
        firstDate: today,
        lastDate: today.add(const Duration(days: 730)));
    if (!mounted || date == null) return;
    final clock = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(previous));
    if (!mounted || clock == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, clock.hour, clock.minute);
    setState(() {
      if (start) {
        _start = picked;
        if (!_end.isAfter(picked)) _end = picked.add(const Duration(hours: 2));
      } else {
        _end = picked;
      }
    });
  }

  void _finish() {
    final title = _title.text.trim();
    if (title.isEmpty ||
        !_start.isAfter(DateTime.now()) ||
        !_end.isAfter(_start)) {
      showGxSnack(
          context, 'Enter a title and choose future start and end times.');
      return;
    }
    Navigator.of(context).pop((title: title, start: _start, end: _end));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null
          ? 'Add outside booking' : 'Edit outside booking')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(
              controller: _title,
              maxLength: 160,
              decoration: const InputDecoration(labelText: 'Booking title')),
          ListTile(
              title: const Text('Starts'),
              subtitle: Text(eventDate(_start)),
              onTap: () => _pick(true)),
          ListTile(
              title: const Text('Ends'),
              subtitle: Text(eventDate(_end)),
              onTap: () => _pick(false)),
          GxButton(label: widget.existing == null
            ? 'Save booking' : 'Save changes', onTap: _finish),
        ]),
      );
}
