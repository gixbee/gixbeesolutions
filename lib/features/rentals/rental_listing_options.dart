/// Shared labels for rental listing controls (owner form + customer detail).
const kRentalCategories = <(String, String)>[
  ('TOOLS', 'Tools'),
  ('DRILL', 'Drill'),
  ('CAMERA', 'Camera'),
  ('FURNITURE', 'Furniture'),
  ('VEHICLE', 'Vehicle accessories'),
  ('ELECTRONICS', 'Electronics'),
  ('PARTY', 'Party / events'),
  ('SPORTS', 'Sports'),
  ('OTHER', 'Other'),
];

const kRentalConditions = <(String, String)>[
  ('NEW', 'New'),
  ('GOOD', 'Good'),
  ('USED', 'Used'),
];

const kRentalCancelPolicies = <(String, String, String)>[
  (
    'FLEXIBLE',
    'Flexible',
    'Full refund of the booking advance until handover.'
  ),
  (
    'MODERATE',
    'Moderate',
    'Full refund until 24 hours before start. Then 50% of the advance until handover.'
  ),
  (
    'STRICT',
    'Strict',
    'Full refund only before the store confirms. After confirm, the advance is kept.'
  ),
  (
    'NON_REFUNDABLE',
    'Non-refundable',
    'Advance is kept once paid. The refundable deposit is still returned after a good return.'
  ),
];

const kRentalWeekdays = <(int, String)>[
  (1, 'Mon'),
  (2, 'Tue'),
  (3, 'Wed'),
  (4, 'Thu'),
  (5, 'Fri'),
  (6, 'Sat'),
  (7, 'Sun'),
];

String rentalCategoryLabel(String? code) {
  for (final c in kRentalCategories) {
    if (c.$1 == code) return c.$2;
  }
  return 'Other';
}

String rentalConditionLabel(String? code) {
  for (final c in kRentalConditions) {
    if (c.$1 == code) return c.$2;
  }
  return 'Good';
}

(String, String) rentalCancelPolicyCopy(String? code) {
  for (final p in kRentalCancelPolicies) {
    if (p.$1 == code) return (p.$2, p.$3);
  }
  return (kRentalCancelPolicies.first.$2, kRentalCancelPolicies.first.$3);
}

String rentalMinutesLabel(int? minutes) {
  if (minutes == null) return '';
  final h = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final tod = TimeOfDayLike(h, m);
  return tod.label;
}

class TimeOfDayLike {
  const TimeOfDayLike(this.hour, this.minute);
  final int hour;
  final int minute;
  String get label {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final am = hour < 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$h12:$mm ${am ? 'AM' : 'PM'}';
  }
}

int minutesFromHourMinute(int hour, int minute) => hour * 60 + minute;

String rentalAvailabilitySummary({
  String? availableFrom,
  String? availableUntil,
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  int? slotStart,
  int? slotEnd,
}) {
  final days = weekdays.length >= 7
      ? 'Every day'
      : kRentalWeekdays
          .where((d) => weekdays.contains(d.$1))
          .map((d) => d.$2)
          .join(', ');
  final range = [
    if (availableFrom != null &&
        availableFrom.isNotEmpty &&
        availableFrom != 'null')
      'from $availableFrom',
    if (availableUntil != null &&
        availableUntil.isNotEmpty &&
        availableUntil != 'null')
      'until $availableUntil',
  ].join(' ');
  final hours = (slotStart != null && slotEnd != null)
      ? '${rentalMinutesLabel(slotStart)}–${rentalMinutesLabel(slotEnd)}'
      : 'any time';
  return [
    days,
    if (range.isNotEmpty) range,
    hours,
  ].where((s) => s.isNotEmpty).join(' · ');
}

List<int> parseWeekdays(dynamic raw) {
  if (raw is List) {
    final days = raw
        .map((e) => int.tryParse('$e'))
        .whereType<int>()
        .where((d) => d >= 1 && d <= 7)
        .toSet()
        .toList()
      ..sort();
    if (days.isNotEmpty) return days;
  }
  return [1, 2, 3, 4, 5, 6, 7];
}

DateTime? parseYmd(dynamic raw) {
  final s = '$raw'.trim();
  if (s.isEmpty || s == 'null') return null;
  if (s.length >= 10) {
    return DateTime.tryParse(s.substring(0, 10));
  }
  return DateTime.tryParse(s);
}

String? ymd(DateTime? d) =>
    d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
