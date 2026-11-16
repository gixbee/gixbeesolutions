import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../repositories/business_repository.dart';
import '../../repositories/events_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_snackbar.dart';
import 'event_plan_detail_screen.dart';
import 'photography_calendar_math.dart';
import 'event_plans_screen.dart';
import 'event_vendor_calendar_screen.dart';

/// Owner's photography schedule. Confirmed Gixbee quotes and outside shoots
/// originate from Rust; unavailable days reuse the existing Business API.
class PhotographyOwnerCalendarScreen extends ConsumerStatefulWidget {
  const PhotographyOwnerCalendarScreen({super.key, required this.business});
  final Business business;

  @override
  ConsumerState<PhotographyOwnerCalendarScreen> createState() =>
      _PhotographyOwnerCalendarScreenState();
}

class _PhotographyOwnerCalendarScreenState
    extends ConsumerState<PhotographyOwnerCalendarScreen> {
  static const _navy = Color(0xFF1B2559);
  static const _green = Color(0xFF12B76A);
  static const _light = Color(0xFFECFDF3);
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateUtils.dateOnly(DateTime.now());
  late Future<List<Map<String, dynamic>>> _bookings = _loadBookings();
  final _blocked = <String>{};
  String _tab = 'calendar';
  bool _busy = false;
  bool _settingsLoaded = false;
  String? _settingsError;
  int _revision = 0;
  Map<String, dynamic> _catalogue = {};
  int _dailyLimit = 1;
  int _advanceDays = 365;
  int _noticeDays = 0;

  String _key(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  @override
  void initState() {
    super.initState();
    _blocked.addAll(widget.business.offlineDays.map(_key));
    _loadSettings();
  }

  Future<List<Map<String, dynamic>>> _loadBookings() =>
      ref.read(eventsRepositoryProvider)
          .photographyCalendar(widget.business.id);

  Future<void> _loadSettings() async {
    try {
      final result = await ref.read(eventsRepositoryProvider)
          .catalogue(widget.business.id, 'PHOTOGRAPHY');
      if (!mounted) return;
      final c = Map<String, dynamic>.from(
          result['catalogue'] as Map? ?? {});
      setState(() {
        _revision = (result['revision'] as num?)?.toInt() ?? 0;
        _catalogue = c;
        _dailyLimit = (c['maxBookingsPerDay'] as num?)?.toInt() ?? 1;
        _advanceDays = (c['maxAdvanceDays'] as num?)?.toInt() ?? 365;
        _noticeDays = (c['minNoticeDays'] as num?)?.toInt() ?? 0;
        _settingsLoaded = true;
        _settingsError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _settingsError = eventError(error));
    }
  }

  Future<void> _refresh() async {
    setState(() => _bookings = _loadBookings());
    await _loadSettings();
  }

  DateTime? _begin(Map<String, dynamic> item) =>
      PhotographyCalendarMath.inIndia(item['startAt']);

  DateTime? _finish(Map<String, dynamic> item) =>
      PhotographyCalendarMath.inIndia(item['endAt']);

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _forDay(
      List<Map<String, dynamic>> items, DateTime date) =>
      PhotographyCalendarMath.onDay(items, date);

  Future<void> _markOffline(bool blocked) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(businessRepositoryProvider);
      if (blocked) {
        await repo.addOfflineDay(widget.business.id, _selected);
      } else {
        await repo.removeOfflineDay(widget.business.id, _selected);
      }
      if (!mounted) return;
      setState(() {
        if (blocked) { _blocked.add(_key(_selected)); }
        else { _blocked.remove(_key(_selected)); }
      });

    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_busy || !_settingsLoaded || _noticeDays > _advanceDays) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(eventsRepositoryProvider).saveCatalogue(
        widget.business.id, 'PHOTOGRAPHY', _revision,
        {
          ..._catalogue,
          'maxBookingsPerDay': _dailyLimit,
          'maxAdvanceDays': _advanceDays,
          'minNoticeDays': _noticeDays,
        },
      );
      if (!mounted) return;
      setState(() {
        _revision = (result['revision'] as num).toInt();
        _catalogue = Map<String,dynamic>.from(result['catalogue'] as Map);
      });
      showGxSnack(context, 'Booking settings saved');
    } catch (error) {
      if (mounted) showGxSnack(context, eventError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOutsideBookings() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => EventVendorCalendarScreen(
        businessId: widget.business.id),
    ));
    if (mounted) await _refresh();
  }

  Future<void> _openPlan(Map<String, dynamic> item) async {
    final id = item['planId'];
    if (id is! String || id.isEmpty) return;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => EventPlanDetailScreen(planId: id),
    ));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calendar & Bookings'),
      actions: [
        IconButton(
          tooltip: 'Refresh calendar',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh)),
      ]),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Row(children: [
          for (final (tab, label) in const [
            ('calendar','Calendar'), ('register','Bookings'), ('settings','Settings')
          ])
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: _tab == tab,
                onSelected: (_) => setState(() => _tab = tab),
              ),
            )),
        ]),
      ),
      if (_tab == 'settings')
        Expanded(child: _settingsBody())
      else
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _bookings,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: TextButton(
                onPressed: _refresh,
                child: Text('${eventError(snapshot.error!)} Retry')));
            }
            final entries = snapshot.data ?? [];
            return _tab == 'register' ?
                _registerBody(entries) : _calendarBody(entries);
          },
        )),
    ])),
  );

  Widget _monthBar() => Row(children: [
    IconButton(
      tooltip: 'Previous month',
      icon: const Icon(Icons.chevron_left),
      onPressed: () => setState(() =>
          _month = DateTime(_month.year, _month.month - 1)),
    ),
    Expanded(child: Text(DateFormat('MMMM yyyy').format(_month),
      textAlign: TextAlign.center,
      style: const TextStyle(color: _navy, fontSize: 17,
        fontWeight: FontWeight.w900))),
    IconButton(
      tooltip: 'Next month',
      icon: const Icon(Icons.chevron_right),
      onPressed: () => setState(() =>
          _month = DateTime(_month.year, _month.month + 1)),
    ),
  ]);

  Widget _calendarBody(List<Map<String, dynamic>> entries) {
    final first = DateTime(_month.year, _month.month, 1);
    final pad = first.weekday % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final selectedRows = _forDay(entries, _selected);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      children: [
        _monthBar(),
        const SizedBox(height: 6),
        Row(children: [
          for (final label in const ['S','M','T','W','T','F','S'])
            Expanded(child: Text(label, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.blueGrey))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: pad + days,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, mainAxisSpacing: 4,
            crossAxisSpacing: 4, childAspectRatio: 0.8),
          itemBuilder: (context, index) {
            if (index < pad) return const SizedBox.shrink();
            final date = DateTime(_month.year, _month.month, index - pad + 1);
            final booked = _forDay(entries, date).length;
            final blocked = _blocked.contains(_key(date));
            final full = booked >= _dailyLimit;
            final selected = _same(date, _selected);
            final color = blocked ? Colors.grey :
                full ? Colors.redAccent :
                booked > 0 ? Colors.orange : _green;
            return InkWell(
              key: ValueKey('photo-day-${_key(date)}'),
              onTap: () => setState(() => _selected = date),
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? _light : Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected ? _green : const Color(0xFFE2E8F0),
                    width: selected ? 2 : 1)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${date.day}', style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12)),
                    if (booked > 0)
                      Text('$booked/$_dailyLimit',
                        style: const TextStyle(fontSize: 9)),
                    Container(height: 5, width: 5,
                      decoration: BoxDecoration(
                        color: color, shape: BoxShape.circle)),
                  ]),
              ),
            );
          },
        ),
        const SizedBox(height: 9),
        const Text('Green: open · Orange: shoots · Red: full · Grey: unavailable',
            style: TextStyle(color: Colors.blueGrey, fontSize: 11)),
        const Divider(height: 30),
        Text(DateFormat('EEE, d MMM yyyy').format(_selected),
          style: const TextStyle(color: _navy,
              fontWeight: FontWeight.w900, fontSize: 17)),
        if (_blocked.contains(_key(_selected)))
          const Chip(label: Text('Marked unavailable')),
        Row(children: [
          TextButton.icon(
            onPressed: _busy ? null :
              () => _markOffline(!_blocked.contains(_key(_selected))),
            icon: Icon(_blocked.contains(_key(_selected)) ?
                Icons.event_available : Icons.event_busy),
            label: Text(_blocked.contains(_key(_selected))
                ? 'Mark available' : 'Mark unavailable'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _openOutsideBookings,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add shoot'),
          ),
        ]),
        if (selectedRows.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
            child: Text('No shoots are scheduled for this date.')),
        for (final row in selectedRows) _bookingCard(row),
      ],
    );
  }

  Widget _registerBody(List<Map<String, dynamic>> items) {
    final monthEntries = items.where((item) =>
        PhotographyCalendarMath.overlapsMonth(item, _month))
        .toList()..sort((a,b) =>
            (_begin(a) ?? DateTime.utc(1900))
                .compareTo(_begin(b) ?? DateTime.utc(1900)));
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        _monthBar(),
        Card(color: _light,
          child: ListTile(
            title: Text('${monthEntries.length} shoots in this month',
              style: const TextStyle(color: _navy,
                fontWeight: FontWeight.w900)),
            subtitle: Text(
              '${monthEntries.where((x)=>x['source']=='gixbee').length} Gixbee · '
              '${monthEntries.where((x)=>x['source']=='offline').length} outside'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _openOutsideBookings,
          icon: const Icon(Icons.add),
          label: const Text('Manage outside bookings'),
        ),
        if (monthEntries.isEmpty)
          const Padding(padding: EdgeInsets.all(16),
            child: Text('No shoots in this month.')),
        for (final row in monthEntries)
          _bookingCard(row),
        const SizedBox(height: 9),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) =>
              EventPlansScreen(business: widget.business, bookingsOnly: true),
          )),
          child: const Text('Open Gixbee booking register'),
        ),
      ],
    );
  }

  Widget _bookingCard(Map<String,dynamic> item) {
    final start = _begin(item), end = _finish(item);
    final platform = item['source'] == 'gixbee';
    return Card(
      child: ListTile(
        leading: Icon(platform ? Icons.verified_user_outlined :
            Icons.photo_camera_outlined, color: _navy),
        title: Text(item['title']?.toString() ?? 'Photography shoot',
          style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text([
          if (start != null)
            '${DateFormat('EEE d MMM · hh:mm a').format(start)} IST',
          if (end != null)
            'Until ${DateFormat('hh:mm a').format(end)} IST',
          platform ? 'Gixbee · ${item['status'] ?? 'Confirmed'}' : 'Outside booking',
          if ((item['location']?.toString() ?? '').isNotEmpty)
            item['location'].toString(),
        ].join('\n')),
        trailing: platform ? const Icon(Icons.chevron_right) : null,
        onTap: platform ? () => _openPlan(item) : _openOutsideBookings,
      ),
    );
  }

  Widget _settingsBody() {
    if (!_settingsLoaded) {
      return Center(child: _settingsError == null
        ? const CircularProgressIndicator()
        : TextButton(onPressed: _loadSettings,
            child: Text('$_settingsError · Retry')));
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Booking settings',
        style: TextStyle(color: _navy,
          fontWeight: FontWeight.w900, fontSize: 20)),
      const SizedBox(height: 14),
      const Text('Maximum bookings per day',
        style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 7, children: [
        for (final n in const [1, 2, 3, 4, 5, 6])
          ChoiceChip(label: Text('$n'),
            selected: _dailyLimit == n,
            onSelected: _busy ? null : (_) =>
              setState(() => _dailyLimit = n)),
      ]),
      const SizedBox(height: 10),
      Text('You can confirm up to $_dailyLimit shoots per day.',
        style: const TextStyle(color: Colors.blueGrey)),
      const SizedBox(height: 18),
      const Text('Customer booking window',
        style: TextStyle(fontWeight: FontWeight.w800)),
      Wrap(spacing: 7, children: [
        for (final (days, name) in const [
          (90,'3 mo'),(180,'6 mo'),(270,'9 mo'),(365,'12 mo')
        ])
          ChoiceChip(label: Text(name),
            selected: _advanceDays == days,
            onSelected: _busy ? null : (_) =>
              setState(() {
                _advanceDays = days;
                if (_noticeDays > _advanceDays) _noticeDays = 0;
              })),
      ]),
      const SizedBox(height: 18),
      const Text('Minimum notice before an event',
        style: TextStyle(fontWeight: FontWeight.w800)),
      Wrap(spacing: 7, children: [
        for (final n in const [0,1,2,3,7])
          ChoiceChip(label: Text(n == 0 ? 'Same day' : '$n days'),
            selected: _noticeDays == n,
            onSelected: _busy ? null : (_) =>
              setState(() => _noticeDays = n)),
      ]),
      const SizedBox(height: 18),
      const Text('These settings are shared with the owner catalogue and '
          'used by the Rust booking validation API.',
        style: TextStyle(color: Colors.blueGrey)),
      const SizedBox(height: 10),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: _green,
          padding: const EdgeInsets.symmetric(vertical: 14)),
        onPressed: _busy ? null : _saveSettings,
        child: Text(_busy ? 'Saving...' : 'Save booking settings'),
      ),
    ]);
  }
}
