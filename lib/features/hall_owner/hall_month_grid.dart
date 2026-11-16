import 'package:flutter/material.dart';

/// A local-venue calendar view of existing hall blocks and reservations.
/// Incoming timestamps remain UTC; the grid interprets them in venue time.
class HallMonthGrid extends StatelessWidget {
  const HallMonthGrid({
    super.key,
    required this.month,
    required this.venueOffset,
    required this.blocks,
    required this.reservations,
    required this.onSelectDate,
  });

  final DateTime month;
  final Duration venueOffset;
  final List<Map<String, dynamic>> blocks;
  final List<Map<String, dynamic>> reservations;
  final ValueChanged<DateTime> onSelectDate;

  bool _overlaps(Map<String, dynamic> item, DateTime day) {
    final start = DateTime.tryParse('${item['startAt'] ?? ''}')?.toUtc();
    final end = DateTime.tryParse('${item['endAt'] ?? ''}')?.toUtc();
    if (start == null || end == null) return false;
    final midnightUtc =
        DateTime.utc(day.year, day.month, day.day).subtract(venueOffset);
    return start.isBefore(midnightUtc.add(const Duration(days: 1))) &&
        end.isAfter(midnightUtc);
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF1B2559);
    final first = DateTime(month.year, month.month);
    final weekdayOffset = first.weekday % 7;
    final count = DateUtils.getDaysInMonth(month.year, month.month);
    final now = DateTime.now().toUtc().add(venueOffset);
    final today = DateTime(now.year, now.month, now.day);
    return SingleChildScrollView(
      child: Column(children: [
      Row(children: [
        for (final name in ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'])
          Expanded(
              child: Center(
                  child: Text(name,
                      style: const TextStyle(
                          color: navy,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)))),
      ]),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          childAspectRatio: 0.90,
        ),
        itemCount: weekdayOffset + count,
        itemBuilder: (_, index) {
          if (index < weekdayOffset) return const SizedBox.shrink();
          final date =
              DateTime(month.year, month.month, index - weekdayOffset + 1);
          final blocked = blocks.any((item) => _overlaps(item, date));
          final confirmed = reservations.any(
              (item) => item['status'] == 'CONFIRMED' && _overlaps(item, date));
          final held = !confirmed &&
              reservations.any(
                  (item) => item['status'] == 'HELD' && _overlaps(item, date));
          final isToday = date == today;
          final inPast = date.isBefore(today);
          final background = blocked
              ? const Color(0xFFFEE2E2)
              : confirmed
                  ? const Color(0xFFDCFCE7)
                  : held
                      ? const Color(0xFFFFF3C4)
                      : Colors.white;
          return InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: inPast ? null : () => onSelectDate(date),
            child: Container(
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isToday
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFE2E8F0),
                  width: isToday ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${date.day}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: inPast ? Colors.grey : navy)),
                  if (blocked || confirmed || held)
                    Icon(
                        blocked
                            ? Icons.block
                            : confirmed
                                ? Icons.check_circle
                                : Icons.schedule,
                        size: 12,
                        color: blocked
                            ? const Color(0xFFB91C1C)
                            : confirmed
                                ? const Color(0xFF047857)
                                : const Color(0xFFB45309)),
                ],
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 10),
      const Wrap(spacing: 12, runSpacing: 6, children: [
        Text('Available', style: TextStyle(fontSize: 11)),
        Text('🟢 Confirmed', style: TextStyle(fontSize: 11)),
        Text('🟡 Held', style: TextStyle(fontSize: 11)),
        Text('🔴 Blocked', style: TextStyle(fontSize: 11)),
      ]),
      const SizedBox(height: 5),
      const Text('Tap a date to block a full day or a selected slot.',
          style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
    ]),
    );
  }
}
