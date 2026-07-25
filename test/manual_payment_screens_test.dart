import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/booking/collect_payment_screen.dart';
import 'package:gixbee/features/booking/customer_pay_screen.dart';
import 'package:gixbee/features/booking/manual_payment_billing.dart';
import 'package:gixbee/repositories/booking_repository.dart';
import 'package:gixbee/theme.dart';

class _FakeBookingRepo extends BookingRepository {
  _FakeBookingRepo() : super(Dio());

  @override
  Future<Map<String, dynamic>?> getBookingById(String id) async => {
        'id': id,
        'totalAmount': 156,
        'amount': 130,
        'type': 'INSTANT',
        'workedMinutes': 72,
        'pausedMinutes': 22,
        'hourlyRate': 130,
        'platformFee': 12,
        'customer': {'name': 'Suresh'},
        'operator': {'name': 'Rajesh'},
      };

  @override
  Future<Map<String, dynamic>> markPaid(
    String bookingId, {
    String? collectionMethod,
    String? honestyCheck,
    String? safetyCheck,
  }) async =>
      {
        'message': 'ok',
        'isPaid': true,
        'workerPaidConfirmed': true,
        'customerPaidConfirmed': true,
      };
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(_FakeBookingRepo()),
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [GxColors.dark],
        ),
        home: home,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManualPaymentBilling', () {
    test('formats duration and pause labels', () {
      const b = ManualPaymentBilling(
        amount: 156,
        hourlyRate: 130,
        workedMinutes: 72,
        pausedMinutes: 22,
        platformFee: 12,
        counterpartName: 'Suresh',
      );
      expect(b.compactDurationLabel, '1hr 12min');
      expect(b.durationLabel, '1 hr 12 min');
      expect(b.pauseLabel, '22 min · ₹0');
      expect(b.amountInt, 156);
    });
  });

  group('CollectPaymentScreen', () {
    testWidgets('shows collect copy, honesty check and confirm CTA',
        (tester) async {
      await _pump(
        tester,
        const CollectPaymentScreen(
          bookingId: 'b1',
          amount: 156,
          customerName: 'Suresh',
          hourlyRate: 130,
          workedMinutes: 72,
          pausedMinutes: 22,
          platformFee: 12,
        ),
      );

      expect(find.text('Collect ₹156'), findsOneWidget);
      expect(find.text('Collect from customer then confirm'), findsOneWidget);
      expect(find.text('Honesty check'), findsOneWidget);
      expect(find.text('Payment received · Confirm'), findsOneWidget);
      expect(find.textContaining('Gixbee fee'), findsWidgets);
    });
  });

  group('CustomerPayScreen', () {
    testWidgets('shows pay copy, methods, safety check and confirm CTA',
        (tester) async {
      await _pump(
        tester,
        const CustomerPayScreen(
          bookingId: 'b1',
          amount: 156,
          workerName: 'Rajesh',
          hourlyRate: 130,
          workedMinutes: 72,
          pausedMinutes: 22,
          platformFee: 12,
        ),
      );

      expect(find.text('Pay Rajesh'), findsOneWidget);
      expect(find.text('Job complete · Pay directly'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('GPay / UPI'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('GPay / UPI'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Quick safety check'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Quick safety check'), findsOneWidget);

      expect(find.text('I paid ₹156 · Confirm'), findsOneWidget);
    });
  });
}
