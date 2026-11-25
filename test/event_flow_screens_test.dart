import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/catering_package_wizard_screen.dart';
import 'package:gixbee/features/events/event_plan_create_screen.dart';
import 'package:gixbee/features/events/hall_booking_review_screen.dart';
import 'package:gixbee/features/events/photography_package_wizard_screen.dart';
import 'package:gixbee/features/events/photography_service_wizard_screen.dart';
import 'package:gixbee/features/hall_owner/hall_month_grid.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    );

void main() {
  test('CateringMenuGroups classifies HTML category titles', () {
    expect(CateringMenuGroups.classify({'category': 'Welcome Drinks'}), 'g01');
    expect(CateringMenuGroups.classify({'category': 'Rice, Biriyani & Mandi'}),
        'g03');
    expect(CateringMenuGroups.classify({'category': 'payasam'}), 'g08');
    expect(CateringMenuGroups.classify({'category': 'unknown-item'}), 'other');
  });

  testWidgets('Catering owner wizard shows first HTML step', (tester) async {
    await tester.pumpWidget(_host(CateringPackageWizardScreen(dishes: const [
      {'id': 'd1', 'name': 'Ghee Rice', 'category': 'g03'},
    ])));
    expect(find.text('Select Package Category *'), findsOneWidget);
    expect(find.text('Wedding & Related Functions'), findsOneWidget);
    expect(find.text('Other Functions'), findsOneWidget);
  });

  testWidgets('Photography package wizard starts on package basics',
      (tester) async {
    await tester.pumpWidget(_host(const PhotographyPackageWizardScreen()));
    expect(find.text('Package name *'), findsOneWidget);
    expect(find.textContaining('Package basics'), findsOneWidget);
  });

  testWidgets('Photography individual service wizard lists categories',
      (tester) async {
    await tester.pumpWidget(_host(const PhotographyServiceWizardScreen()));
    expect(find.text('Portrait & Family'), findsOneWidget);
    expect(find.text('Product Photography'), findsOneWidget);
  });

  testWidgets('Hall customer review requires advance acknowledgement',
      (tester) async {
    await tester.pumpWidget(_host(HallBookingReviewScreen(
      hall: {
        'hallName': 'Lake View',
        'package': {
          'payment': {'advanceType': 'percent', 'advancePct': 30},
          'cancellation': const [],
          'postponement': const [],
        },
      },
      selection: EventServiceSelection(
        businessId: 'b1',
        cityId: 'c1',
        summary: 'Lake View · Morning · With AC\n₹50000',
        request: {'expectedEstimate': 50000, 'hallId': 'h1'},
      ),
      eventType: 'Wedding',
      eventDate: DateTime.utc(2027, 1, 10),
      guests: 200,
    )));
    expect(find.text('Booking Details'), findsOneWidget);
    expect(find.textContaining('₹15,000'), findsWidgets);
    expect(find.text('Request to Book'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('Hall month grid renders weekday headers', (tester) async {
    await tester.pumpWidget(_host(HallMonthGrid(
      month: DateTime(2026, 11, 1),
      venueOffset: Duration.zero,
      blocks: const [],
      reservations: const [],
      onSelectDate: (_) {},
    )));
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
  });
}
