import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_module_picker_screen.dart';

void main() {
  const drinkId = '22222222-2222-4222-8222-222222222222';
  const teaId = '33333333-3333-4333-8333-333333333333';
  final dishes = <Map<String, dynamic>>[
    {'id': drinkId, 'name': 'Mango Welcome Drink', 'diet': 'veg'},
    {'id': teaId, 'name': 'Masala Tea', 'diet': 'veg'},
  ];

  Future<Set<String>?> openPicker(WidgetTester tester, {bool apply = true}) async {
    Set<String>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(body: TextButton(
        onPressed: () async {
          result = await Navigator.of(context).push<Set<String>>(
            MaterialPageRoute(builder: (_) => CateringModulePickerScreen(
              title: 'Welcome Drinks', emoji: '🥤',
              dishes: dishes, selectedIds: {drinkId},
            )),
          );
        },
        child: const Text('Open'),
      )),
    )));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Apply (1)'), findsOneWidget);
    await tester.tap(find.text('Masala Tea'));
    await tester.pumpAndSettle();
    expect(find.text('Apply (2)'), findsOneWidget);
    if (apply) {
      await tester.tap(find.text('Apply (2)'));
    } else {
      await tester.pageBack();
    }
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('Apply preserves existing selection and adds dishes', (tester) async {
    final selection = await openPicker(tester);
    expect(selection, {drinkId, teaId});
  });

  testWidgets('Back does not apply pending changes', (tester) async {
    final selection = await openPicker(tester, apply: false);
    expect(selection, isNull);
  });
}
