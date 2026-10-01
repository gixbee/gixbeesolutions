import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/hall_repository.dart';
import '../../shared/models/business.dart';
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_snackbar.dart';

/// Interval calendar for a hall. Times displayed in venue timezone (IST label).
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  DateTime get _from => DateTime(_month.year, _month.month, 1);
  DateTime get _to => DateTime(_month.year, _month.month + 1, 1);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ref.read(hallRepositoryProvider).getCalendar(
            widget.business.id,
            widget.hallId,
            from: _from.toUtc(),
            to: _to.toUtc(),
          );
      if (!mounted) return;
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
    // Venue civil day Asia/Kolkata (+05:30) → UTC instants.
    final startUtc = DateTime.utc(day.year, day.month, day.day)
        .subtract(const Duration(hours: 5, minutes: 30));
    final endUtc = startUtc.add(const Duration(days: 1));
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
    final tzLabel =
        (_data?['timezoneLabel'] as String?) ?? 'Times shown in IST (Kolkata)';
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
                    title: Text('${b['startAt']} → ${b['endAt']}'),
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
                    title: Text('${m['status']}: ${m['startAt']}'),
                    subtitle: Text('→ ${m['endAt']}'),
                  );
                }),
                const SizedBox(height: 16),
                GxButton(
                  label: 'Block today (full day, venue TZ)',
                  onTap: () => _blockDay(DateTime.now()),
                ),
                const SizedBox(height: 8),
                GxButton(
                  label: 'Block selected month day…',
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _month,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) await _blockDay(picked);
                  },
                ),
              ],
            ),
    );
  }
}
