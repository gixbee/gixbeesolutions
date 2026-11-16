import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/photography_package_wizard_screen.dart';
import 'package:gixbee/features/events/photography_service_wizard_screen.dart';

void main() {
  void setupPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('package save retries in place with same ID, structured values',
      (tester) async {
    setupPhone(tester);
    var calls = 0;
    final attempts = <Map<String,dynamic>>[];
    final existing = <String,dynamic>{
      'id':'11111111-1111-4111-8111-111111111111',
      'name':'Wedding Premium', 'kind':'PACKAGE','active':false,
      'description':'A complete premium wedding shoot',
      'price':90000, 'listPrice':100000,'discountPct':10,
      'functions':['Wedding'], 'ceremonies':['Hindu'],
      'inclusions':['Edited Photos'],
      'paymentSplit':[
        {'label':'Booking advance','percent':30},
        {'label':'Event day','percent':40},
        {'label':'After album','percent':20},
        {'label':'Final','percent':10},
      ],
    };
    await tester.pumpWidget(MaterialApp(home: Builder(builder:(context) =>
      Scaffold(body: Center(child: ElevatedButton(
        onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => PhotographyPackageWizardScreen(
            package: existing,
            onSave: (item) async {
              calls++;
              attempts.add(item);
              return calls > 1;
            },
          ),
        )),
        child: const Text('Open package'),
      )),
    ))));
    await tester.tap(find.text('Open package'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Customer will see: ₹90000'), findsOneWidget);
    for (var i=0; i<9; i++) {
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('Review & publish'), findsWidgets);
    await tester.tap(find.text('Save Package'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Package could not be saved'), findsOneWidget);
    expect(attempts.first['id'], existing['id']);
    expect(attempts.first['active'], false);
    expect(attempts.first['price'], 90000);
    expect(attempts.first['listPrice'], 100000);
    expect(attempts.first['discountPct'], 10);
    expect(attempts.first['functionCoverage'], isA<Map>());
    expect(attempts.first['deliverableDetails'], isA<Map>());
    await tester.tap(find.text('Save Package'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Open package'), findsOneWidget);
  });

  testWidgets('individual service editor saves after callback confirms success',
      (tester) async {
    setupPhone(tester);
    var calls=0;
    Map<String,dynamic>? saved;
    await tester.pumpWidget(MaterialApp(home: Builder(builder:(context) =>
      Scaffold(body: ElevatedButton(
        child: const Text('Open service'),
        onPressed: ()=>Navigator.of(context).push<void>(MaterialPageRoute(
          builder:(_)=>PhotographyServiceWizardScreen(
            service: {
              'id':'22222222-2222-4222-8222-222222222222',
              'name':'Family Portrait','kind':'ITEM','active':true,
              'category':'Portrait & Family',
              'price':8000,'listPrice':10000,'discountPct':20,
            },
            onSave:(item) async {calls++;saved=item;return true;},
          ),
        )),
      )),
    ))));
    await tester.tap(find.text('Open service'));
    await tester.pumpAndSettle();
    for (var i=0;i<7;i++) {
      await tester.tap(find.text('Next →'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Save Service'));
    await tester.pumpAndSettle();
    expect(calls,1);
    expect(saved?['price'], 8000);
    expect(saved?['id'], '22222222-2222-4222-8222-222222222222');
    expect(find.text('Open service'),findsOneWidget);
  });
}
