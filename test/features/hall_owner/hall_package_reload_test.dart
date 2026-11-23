import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/hall_owner/hall_package_wizard_screen.dart';
import 'package:gixbee/repositories/hall_repository.dart';
import 'package:gixbee/shared/models/business.dart';

class SavedHallRepository extends HallRepository {
  SavedHallRepository() : super(Dio());
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> getHall(
          String businessId, String hallId) async =>
      {
        'name': 'Test Hall',
        'spaceType': 'indoor',
        'packageSaved': true,
        'package': saved ??
            {
              'slotOffers': [
                {
                  'id': 'morning',
                  'enabled': true,
                  'hallFrom': '10:00',
                  'hallTo': '15:00',
                  'offerNoAc': false,
                  'offerAc': true,
                  'priceNoAc': 55000,
                  'priceAc': 75000,
                  'discountAcPct': 10,
                  'acUsage': 'partial',
                  'acHours': 2,
                  'acTiming': 'fixed',
                  'acFrom': '11:00',
                  'acTo': '13:00'
                },
              ]
            },
      };

  @override
  Future<Map<String, dynamic>> patchHall(
          String businessId, String hallId, Map<String, dynamic> data) async =>
      data;

  @override
  Future<Map<String, dynamic>> savePackage(
      String businessId, String hallId, Map<String, dynamic> package) async {
    saved = package;
    return {};
  }
}

void main() {
  testWidgets('saved slot choices, discounts and fixed AC survive wizard save',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = SavedHallRepository();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          hallRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
            home: HallPackageWizardScreen(
          business: Business(
              id: 'business',
              name: 'Venue',
              type: 'SERVICE',
              ownerId: 'owner',
              status: 'VERIFIED'),
          hallId: 'hall',
        ))));
    await tester.pumpAndSettle();
    Future<void> next() async {
      await tester.scrollUntilVisible(find.text('Continue'), 500,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    await next();
    await next();
    expect(find.text('Fixed AC schedule'), findsOneWidget);
    expect(
        find.text('Customer will see: ₹75000 • 10% off → ₹67500 (GST incl.)'),
        findsOneWidget);
    await next();
    await next();
    await tester.scrollUntilVisible(find.text('Update Package'), 500,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Update Package'));
    await tester.pumpAndSettle();
    final slot = (repository.saved!['slotOffers'] as List).first as Map;
    expect(slot['offerNoAc'], false);
    expect(slot['discountAcPct'], 10);
    expect(slot['acHours'], 2);
    expect(slot['acFrom'], '11:00');
    expect(slot['acTo'], '13:00');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(ProviderScope(
        overrides: [
          hallRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
            home: HallPackageWizardScreen(
          business: Business(
              id: 'business',
              name: 'Venue',
              type: 'SERVICE',
              ownerId: 'owner',
              status: 'VERIFIED'),
          hallId: 'hall',
        ))));
    await tester.pumpAndSettle();
    await next();
    await next();
    expect(find.text('Fixed AC schedule'), findsOneWidget);
    expect(
        find.text('Customer will see: ₹75000 • 10% off → ₹67500 (GST incl.)'),
        findsOneWidget);
  });
}
