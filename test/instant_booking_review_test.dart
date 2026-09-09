import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/booking/instant_booking_review.dart';
import 'package:gixbee/theme.dart';

void main() {
  testWidgets(
      'review discloses the payable rate, scope, travel and direct payment',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [GxColors.light]),
      home: const Scaffold(
          body: SingleChildScrollView(
              child: InstantBookingReview(
        skill: 'Electrician',
        address: 'Home, confirmed location',
        description: 'Replace the kitchen switch',
        contact: 'Myself',
        languages: ['Hindi', 'English'],
        hourlyRate: 250,
      ))),
    ));
    expect(find.text('Review your request'), findsOneWidget);
    expect(find.text('Your offered rate: ₹250 / hour'), findsOneWidget);
    expect(find.text('Replace the kitchen switch'), findsOneWidget);
    expect(find.textContaining('Minimum service charge: ₹250 (1 hour)'),
        findsOneWidget);
    expect(find.textContaining('Travel is extra'), findsOneWidget);
    expect(
        find.textContaining('Pay the professional directly'), findsOneWidget);
    expect(find.textContaining('Three late cancellations'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review accommodates a small screen and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [GxColors.dark]),
      home: const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
          padding: EdgeInsets.all(20),
          child: InstantBookingReview(
            skill: 'Household cleaning',
            address: 'A long address with a building and landmark',
            description:
                'Clean the kitchen and living room. Bring cleaning supplies.',
            contact: 'A family member at the location',
            languages: ['Malayalam', 'English'],
            hourlyRate: 500,
          ),
        ))),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
