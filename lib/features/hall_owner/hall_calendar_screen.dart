import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

const _kolkataOffset = Duration(hours: 5, minutes: 30);

bool _isKolkata(String tz) => tz == 'Asia/Kolkata' || tz == 'Asia/Calcutta';

Duration _venueOffset(String tz) => _isKolkata(tz) ? _kolkataOffset : Duration.zero;

/// Venue civil clock, stored in calendar fields only.
DateTime _venueNow(String tz) {
  final shifted = DateTime.now().toUtc().add(_venueOffset(tz));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
  );
}

/// UTC instant of civil midnight in the venue timezone.
DateTime _venueMidnightUtc(String tz, int year, int month, [int day = 1]) {
  return DateTime.utc(year, month, day).subtract(_venueOffset(tz));
}

/// Interval calendar for a hall. Month bounds and blocks use the venue timezone.
class HallCalendarScreen extends ConsumerStatefulWidget {
  const HallCalendarScreen({
    super.key,
    required this.business,
    required this.hallId,
  });
  final Business business;
  final String hallId;

  @override
  ConsumerState<HallCalendarScreen> createState() => _HallCalendarScreenState();
}

class _HallCalendarScreenState extends ConsumerState<HallCalendarScreen> {
  late DateTime _month;
  Map<String, dynamic>? _data;
  bool _loading = true;
  String _tz = 'Asia/Kolkata';

  @override
  void initState() {
    super.initState();
    final now = _venueNow(_tz);
    _month = DateTime(now.year, now.month);
    _load();
  }

  DateTime get _from => _venueMidnightUtc(_tz, _month.year, _month.month);
  DateTime get _to => _venueMidnightUtc(_tz, _month.year, _month.month + 1);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(hallRepositoryProvider).getCalendar(
            widget.business.id,
            widget.hallId,
            from: _from,
            to: _to,
          );
      if (!mounted) return;
      final tz = (data['venueTimezone'] as String?) ?? 'Asia/Kolkata';
      if (tz != _tz) {
        final now = _venueNow(tz);
        setState(() {
          _tz = tz;
          _month = DateTime(now.year, now.month);
        });
        await _load();
        return;
      }
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  Future<void> _blockDay(DateTime day) async {
    final startUtc = _venueMidnightUtc(_tz, day.year, day.month, day.day);
    final endUtc = startUtc.add(const Duration(days: 1));
    await _createBlock(startUtc, endUtc);
  }

  Future<void> _chooseBlock(DateTime day) async {
    try {
      final data = await ref.read(hallRepositoryProvider)
          .getPackage(widget.business.id, widget.hallId);
      if (!mounted) return;
      final package = data['package'] as Map?;
      final slots = ((package?['slotOffers'] as List?) ?? []).whereType<Map>()
          .where((slot) => slot['enabled'] != false).toList();
      final selection = await showDialog<Map>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Block availability'),
          children: [
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, const {}),
              child: const Text('Full day')),
            for (final slot in slots)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, slot),
                child: Text('${slot['label']} · ${slot['hallFrom']}–${slot['hallTo']}'),
              ),
          ],
        ),
      );
      if (!mounted || selection == null) return;
      if (selection.isEmpty) {
        await _blockDay(day);
        return;
      }
      final midnight = _venueMidnightUtc(_tz, day.year, day.month, day.day);
      DateTime at(String value) {
        final parts = value.split(':');
        return midnight.add(Duration(hours: int.parse(parts[0]), minutes: int.parse(parts[1])));
      }
      await _createBlock(at(selection['hallFrom'] as String), at(selection['hallTo'] as String));
    } catch (error) {
      if (mounted) showGxSnack(context, '$error', type: GxSnackType.error);
    }
  }

  Future<void> _createBlock(DateTime startUtc, DateTime endUtc) async {
    try {
      await ref.read(hallRepositoryProvider).createBlock(
        widget.business.id,
        widget.hallId,
        {
          'startAt': startUtc.toIso8601String(),
          'endAt': endUtc.toIso8601String(),
          'reason': 'offline',
          'notes': 'Blocked from app',
        },
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  String _venueStamp(Object? raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}');
    if (parsed == null) return '${raw ?? ''}';
    final kolkata = _isKolkata(_tz);
    final local = parsed.toUtc().add(_venueOffset(_tz));
    String two(int n) => n.toString().padLeft(2, '0');
    final clock =
        '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
    return kolkata ? clock : '$clock UTC';
  }

  Future<void> _release(String blockId) async {
    try {
      await ref
          .read(hallRepositoryProvider)
          .releaseBlock(widget.business.id, blockId);
      _load();
    } catch (e) {
      if (!mounted) return;
      showGxSnack(context, '$e', type: GxSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kolkata = _isKolkata(_tz);
    final tzLabel = kolkata
        ? ((_data?['timezoneLabel'] as String?) ?? 'Times shown in IST (Kolkata)')
        : 'Times shown in UTC ($_tz)';
    final blocks = (_data?['blocks'] as List?) ?? [];
    final reservations = (_data?['reservations'] as List?) ?? [];
    final activeBlocks = blocks
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((b) => b['releasedAt'] == null)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hall calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month - 1));
              _load();
            },
          ),
          Center(
            child: Text(
              '${_month.year}-${_month.month.toString().padLeft(2, '0')}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() => _month = DateTime(_month.year, _month.month + 1));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(tzLabel,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Text('Active blocks (${activeBlocks.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                ...activeBlocks.map((b) {
                  return ListTile(
                    title: Text('${_venueStamp(b['startAt'])} → ${_venueStamp(b['endAt'])}'),
                    subtitle: Text('${b['reason']} · ${b['notes'] ?? ''}'),
                    trailing: TextButton(
                      onPressed: () => _release(b['id'] as String),
                      child: const Text('Release'),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                Text('Reservations (${reservations.length})',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                ...reservations.whereType<Map>().map((r) {
                  final m = Map<String, dynamic>.from(r);
                  return ListTile(
                    title: Text('${m['status']}: ${_venueStamp(m['startAt'])}'),
                    subtitle: Text('→ ${_venueStamp(m['endAt'])}'),
                  );
                }),
                const SizedBox(height: 16),
                GxButton(
                  label: 'Block today (full day, venue TZ)',
                  onTap: () {
                    final today = _venueNow(_tz);
                    _blockDay(DateTime(today.year, today.month, today.day));
                  },
                ),
                const SizedBox(height: 8),
                GxButton(
                  label: 'Block selected month day…',
                  onTap: () async {
                    final today = _venueNow(_tz);
                    final first = DateTime(today.year, today.month, today.day)
                        .subtract(const Duration(days: 1));
                    final last = DateTime(today.year, today.month, today.day)
                        .add(const Duration(days: 730));
                    var initial = DateTime(_month.year, _month.month, 1);
                    if (initial.isBefore(first)) initial = first;
                    if (initial.isAfter(last)) initial = last;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: initial,
                      firstDate: first,
                      lastDate: last,
                    );
                    if (picked != null && mounted) await _chooseBlock(picked);
                  },
                ),
              ],
            ),
    );
  }
}
