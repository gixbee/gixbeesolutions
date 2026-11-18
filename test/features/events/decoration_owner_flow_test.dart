import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/decoration_entry_screen.dart';
import 'package:gixbee/features/events/decoration_price_math.dart';

void main() {
  test('decoration list price and offer use integer half-up rounding', () {
    expect(DecorationPriceMath.offerPrice(101, 50), 51);
    expect(DecorationPriceMath.offerPrice(20000, 10), 18000);
    expect(DecorationPriceMath.offerPrice(1000, 0), 1000);
    expect(DecorationPriceMath.isValid(1, 90), isTrue);
    expect(DecorationPriceMath.isValid(0, 10), isFalse);
    expect(DecorationPriceMath.isValid(101, 91), isFalse);
    expect(() => DecorationPriceMath.offerPrice(101, -1), throwsRangeError);
  });

  testWidgets('owner creates a decoration package and saves a server-ready entry',
      (tester) async {
    tester.view.physicalSize = const Size(440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: Center(child: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => DecorationEntryScreen(
              onSave: (entry) async {
                saved = entry;
                return true;
              },
            ),
          )),
          child: const Text('Open editor'),
        )),
      )),
    ));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Listing name *'),
      'Wedding Stage',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'List price (₹) *'),
      '20000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Discount (%)'),
      '10',
    );
    await tester.ensureVisible(find.text('Save listing'));
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!['kind'], 'PACKAGE');
    expect(saved!['active'], true);
    expect(saved!['addon'], false);
    expect(saved!['price'], 18000);
    expect(saved!['listPrice'], 20000);
    expect(saved!['discountPct'], 10);
    expect(saved!['name'], 'Wedding Stage');
    expect(find.text('Open editor'), findsOneWidget);
  });

  testWidgets('existing add-on can be saved as draft without losing its id',
      (tester) async {
    tester.view.physicalSize = const Size(440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? saved;
    final original = <String, dynamic>{
      'id': '123e4567-e89b-42d3-a456-426614174001',
      'name': 'Flower arch',
      'kind': 'ITEM',
      'price': 2500,
      'listPrice': 2500,
      'discountPct': 0,
      'active': true,
      'addon': true,
    };
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => DecorationEntryScreen(
              item: original,
              onSave: (entry) async {
                saved = entry;
                return true;
              },
            ),
          )),
          child: const Text('Edit'),
        ),
      )),
    ));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save as draft'));
    await tester.pumpAndSettle();
    expect(saved!['id'], original['id']);
    expect(saved!['kind'], 'ITEM');
    expect(saved!['addon'], true);
    expect(saved!['active'], false);
  });
}
