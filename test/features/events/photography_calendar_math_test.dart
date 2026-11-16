import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/photography_calendar_math.dart';

void main() {
  final lateNight = <String,dynamic>{
    'source':'gixbee',
    'startAt':'2026-12-15T22:00:00Z',
    'endAt':'2026-12-16T01:00:00Z',
  };
  final acrossMonth = <String,dynamic>{
    'source':'offline',
    'startAt':'2026-11-30T16:00:00Z',
    'endAt':'2026-12-01T03:00:00Z',
  };

  test('books are grouped by India Standard Time, not runner timezone', () {
    final start = PhotographyCalendarMath.inIndia(
      lateNight['startAt'])!;
    expect((start.year,start.month,start.day,start.hour,start.minute),
      (2026,12,16,3,30));
    expect(PhotographyCalendarMath.overlapsDay(lateNight,
      DateTime(2026,12,15)), isFalse);
    expect(PhotographyCalendarMath.overlapsDay(lateNight,
      DateTime(2026,12,16)), isTrue);
  });

  test('multi-day shoots occupy both dates and their month views', () {
    expect(PhotographyCalendarMath.overlapsDay(acrossMonth,
      DateTime(2026,11,30)), isTrue);
    expect(PhotographyCalendarMath.overlapsDay(acrossMonth,
      DateTime(2026,12,1)), isTrue);
    expect(PhotographyCalendarMath.overlapsMonth(acrossMonth,
      DateTime(2026,11)), isTrue);
    expect(PhotographyCalendarMath.overlapsMonth(acrossMonth,
      DateTime(2026,12)), isTrue);
  });

  test('invalid and end-at-midnight intervals do not overcount', () {
    expect(PhotographyCalendarMath.overlapsDay({
      'startAt':'2026-12-14T18:00:00Z',
      'endAt':'2026-12-14T18:30:00Z',
    },DateTime(2026,12,15)), isFalse); // ends exactly at 00:00 IST
    expect(PhotographyCalendarMath.overlapsDay({
      'startAt':'2026-12-15T12:00:00Z',
      'endAt':'2026-12-15T12:00:00Z',
    },DateTime(2026,12,15)), isFalse);
    expect(PhotographyCalendarMath.onDay([
      lateNight,
      {'startAt':'bad', 'endAt':'bad'},
    ],DateTime(2026,12,16)).length, 1);
  });
}
