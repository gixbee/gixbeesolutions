/// Date grouping for photography bookings uses India Standard Time, matching
/// the Rust booking capacity validator's Asia/Kolkata business day.
/// Returned DateTime values contain IST clock components (no timezone label).
class PhotographyCalendarMath {
  const PhotographyCalendarMath._();
  static const _indiaOffset = Duration(hours: 5, minutes: 30);

  static DateTime? inIndia(Object? timestamp) {
    final parsed = DateTime.tryParse(timestamp?.toString() ?? '');
    return parsed?.toUtc().add(_indiaOffset);
  }

  static bool overlapsDay(Map row, DateTime day) {
    final start = inIndia(row['startAt']);
    final end = inIndia(row['endAt']);
    if (start == null || end == null || !end.isAfter(start)) return false;
    final dayStart = DateTime.utc(day.year, day.month, day.day);
    return start.isBefore(dayStart.add(const Duration(days: 1))) &&
        end.isAfter(dayStart);
  }

  static bool overlapsMonth(Map row, DateTime month) {
    final start = inIndia(row['startAt']);
    final end = inIndia(row['endAt']);
    if (start == null || end == null || !end.isAfter(start)) return false;
    final first = DateTime.utc(month.year, month.month);
    final next = DateTime.utc(month.year, month.month + 1);
    return start.isBefore(next) && end.isAfter(first);
  }

  static List<Map<String,dynamic>> onDay(
      List<Map<String,dynamic>> rows, DateTime day) =>
    rows.where((row) => overlapsDay(row, day)).toList()
      ..sort((a,b) => (inIndia(a['startAt']) ?? DateTime.utc(1900))
          .compareTo(inIndia(b['startAt']) ?? DateTime.utc(1900)));
}
