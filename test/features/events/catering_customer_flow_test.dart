import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_customer_flow_screen.dart';

void main() {
  const drink = '22222222-2222-4222-8222-222222222222';
  const tea = '33333333-3333-4333-8333-333333333333';
  final vendor = <String, dynamic>{
    'businessId': '11111111-1111-4111-8111-111111111111',
    'name': 'Kerala Catering',
    'location': 'Pathanamthitta',
    'catalogue': {
      'about': 'Wedding and celebration catering',
      'photos': <String>[],
      'items': [
        {
          'id': drink, 'kind': 'ITEM', 'active': true,
          'name': 'Mango Welcome Drink', 'diet': 'veg', 'category': 'g01',
          'tiers': [{'minGuests': 1, 'maxGuests': 100, 'price': 100}],
        },
        {
          'id': tea, 'kind': 'ITEM', 'active': true,
          'name': 'Masala Tea', 'diet': 'veg', 'category': 'g01',
          'tiers': [{'minGuests': 1, 'maxGuests': 100, 'price': 50}],
        },
        {
          'id': '55555555-5555-4555-8555-555555555555',
          'kind': 'PACKAGE', 'active': true,
          'name': 'Wedding Feast',
          'category': 'Wedding & Related Functions',
          'diet': 'mixed', 'serveStyle': 'buffet', 'packageLevel': 'Basic',
          'dishIds': [drink, tea],
          'discountPct': 10,
          'baseTiers': [{'minGuests': 1, 'maxGuests': 100, 'price': 500}],
          'tiers': [{'minGuests': 1, 'maxGuests': 100, 'price': 450}],
        },
      ],
    },
  };

  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(child: MaterialApp(
      home: CateringCustomerProfileScreen(
        vendor: vendor,
        cityId: '44444444-4444-4444-8444-444444444444',
        eventType: 'Wedding',
        date: DateTime(2026, 12, 15),
        guests: 30,
        location: 'Pathanamthitta',
        category: 'Wedding & Related Functions',
      ),
    )));
    await tester.tap(find.text('Show Packages / Individual Food Items'));
    await tester.pumpAndSettle();
  }

  testWidgets('package details show the actual offer and categorized menu',
      (tester) async {
    setPhone(tester);
    await openMenu(tester);
    expect(find.text('Wedding Feast'), findsOneWidget);
    await tester.tap(find.text('Wedding Feast'));
    await tester.pumpAndSettle();
    expect(find.text('₹450 / plate'), findsWidgets);
    expect(find.textContaining('Estimated ₹13,500'), findsOneWidget);
    expect(find.text('Welcome Drinks'), findsOneWidget);
    await tester.tap(find.text('Initiate Interest'));
    await tester.pumpAndSettle();
    expect(find.text('Send Interest'), findsWidgets);
    expect(find.text('Event venue / area *'), findsOneWidget);
    expect(find.text('I understand this is an enquiry, not a booking.'),
      findsOneWidget);
  });

  testWidgets('individual dishes can be added and reviewed together',
      (tester) async {
    setPhone(tester);
    await openMenu(tester);
    await tester.tap(find.textContaining('Individual Food Items').first);
    await tester.pumpAndSettle();
    expect(find.text('Mango Welcome Drink'), findsOneWidget);
    await tester.tap(find.byTooltip('Select dish').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select dish').last);
    await tester.pumpAndSettle();
    expect(find.text('Continue with 2 dishes'), findsOneWidget);
    await tester.tap(find.text('Continue with 2 dishes'));
    await tester.pumpAndSettle();
    expect(find.text('2 individual dishes selected'), findsOneWidget);
    expect(find.text('₹4,500'), findsWidgets);
  });
}
