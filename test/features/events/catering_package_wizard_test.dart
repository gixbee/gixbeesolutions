import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_package_wizard_screen.dart';

void main() {
  const dishId = '22222222-2222-4222-8222-222222222222';
  const packageId = '33333333-3333-4333-8333-333333333333';

  testWidgets('existing package survives edit, failed save and retry',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var calls = 0;
    final attempts = <Map<String, dynamic>>[];
    final existing = <String, dynamic>{
      'id': packageId,
      'kind': 'PACKAGE',
      'name': 'Wedding Feast',
      'description': 'Traditional meal',
      'category': 'Wedding & Related Functions',
      'packageLevel': 'Basic',
      'diet': 'veg',
      'serveStyle': 'buffet',
      'dishIds': [dishId],
      'active': false,
      'rateMode': 'tiered',
      'discountPct': 10,
      'baseTiers': [
        {'minGuests': 1, 'maxGuests': 25, 'price': 500},
      ],
      'tiers': [
        {'minGuests': 1, 'maxGuests': 25, 'price': 450},
      ],
    };
    final dishes = <Map<String, dynamic>>[
      {
        'id': dishId, 'kind': 'ITEM', 'name': 'Welcome Drink',
        'diet': 'veg', 'category': 'g01', 'active': true,
      }
    ];

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.push<void>(context,
            MaterialPageRoute(
              builder: (_) => CateringPackageWizardScreen(
                package: existing,
                dishes: dishes,
                onSave: (entry) async {
                  calls++;
                  attempts.add(entry);
                  return calls > 1;
                },
              ),
            )),
          child: const Text('Open editor'),
        )),
      )),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    // Category -> Name -> Selected menu -> Pricing -> Preview.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();
    }
    expect(find.text('1 Dishes'), findsOneWidget);
    await tester.tap(find.text('Next: Set Guest Count Pricing →'));
    await tester.pumpAndSettle();
    expect(find.text('10% off'), findsOneWidget);
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Publish Your Package'), findsOneWidget);

    await tester.tap(find.text('Save Package'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Save Package'), findsOneWidget);
    expect(attempts.single['active'], false);
    expect(attempts.single['id'], packageId);
    expect(attempts.single['discountPct'], 10);
    expect((attempts.single['baseTiers'] as List)[0]['price'], 500);
    expect((attempts.single['tiers'] as List)[0]['price'], 450);
    expect(attempts.single['dishIds'], [dishId]);

    await tester.tap(find.text('Save Package'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Open editor'), findsOneWidget);
    expect(find.text('Save Package'), findsNothing);
  });
}
