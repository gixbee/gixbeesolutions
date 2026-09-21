import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/shared/widgets/gx_sheet.dart';

void main() {
  testWidgets('pinned footer stays visible above the keyboard', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showGxSheet(
                context,
                title: 'Edit item',
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        children: [
                          for (var i = 0; i < 12; i++)
                            SizedBox(height: 48, child: Text('Field $i')),
                        ],
                      ),
                    ),
                    const Text('Save item'),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Save item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
