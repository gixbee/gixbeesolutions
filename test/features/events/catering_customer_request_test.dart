import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_customer_pricing.dart';

void main() {
  final dish = <String, dynamic>{
    'id': '22222222-2222-4222-8222-222222222222',
    'kind': 'ITEM',
    'active': true,
    'tiers': [
      {'minGuests': 1, 'maxGuests': 100, 'price': 125},
    ],
  };
  final now = DateTime(2026, 11, 16, 11);
  final start = DateTime(2026, 12, 15, 10);
  final end = DateTime(2026, 12, 15, 14);

  Map<String, dynamic> make({
    List<Map<String, dynamic>>? selected,
    String notes = '',
    bool customize = false,
    String location = 'Pathanamthitta',
    DateTime? from,
    DateTime? until,
  }) => CateringCustomerRequest.build(
      clientRequestId: '33333333-3333-4333-8333-333333333333',
      businessId: '11111111-1111-4111-8111-111111111111',
      cityId: '44444444-4444-4444-8444-444444444444',
      eventType: 'Wedding',
      location: location,
      start: from ?? start,
      end: until ?? end,
      guests: 30,
      items: selected ?? [dish],
      notes: notes,
      customize: customize,
      servingStyle: 'Buffet Service',
      now: now,
    );

  test('produces Rust targetBusinessId and idempotent request contract', () {
    final payload = make();
    expect(payload['targetBusinessId'],
      '11111111-1111-4111-8111-111111111111');
    expect(payload['clientRequestId'],
      '33333333-3333-4333-8333-333333333333');
    expect(payload['services'], ['CATERING']);
    expect(payload['guestCount'], 30);
    final request = payload['serviceRequest'] as Map;
    expect(request['itemIds'], [dish['id']]);
    expect(request['expectedEstimate'], 3750);
    expect(request.containsKey('customization'), isFalse);
  });

  test('includes bounded custom note and serving preference, not a price override', () {
    final payload = make(
      notes: 'Low spice; add welcome counter', customize: true);
    final request = payload['serviceRequest'] as Map;
    expect(request['expectedEstimate'], 3750);
    expect(request['customization'], {
      'servingStyle': 'Buffet Service',
      'dietaryNeeds': '',
      'menuChanges': 'Low spice; add welcome counter',
    });
  });

  test('rejects invalid selection, past date, venue and long requirement', () {
    expect(() => make(selected: []), throwsFormatException);
    expect(() => make(location: ' '), throwsFormatException);
    expect(() => make(notes: 'a' * 501), throwsFormatException);
    expect(() => make(from: now.subtract(const Duration(hours: 1))),
      throwsFormatException);
    expect(() => make(until: start.subtract(const Duration(minutes: 1))),
      throwsFormatException);
  });
}
