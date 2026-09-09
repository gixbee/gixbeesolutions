import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/booking/instant_request_screen.dart';
import 'package:gixbee/repositories/addresses_repository.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/repositories/booking_repository.dart';
import 'package:gixbee/repositories/worker_repository.dart';
import 'package:gixbee/theme.dart';

void main() {
  testWidgets(
      'request is sent only after review and matches the reviewed details',
      (tester) async {
    final sent = <Map<String, dynamic>>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        if (request.method == 'POST' && request.path == '/bookings/instant') {
          sent.add(Map<String, dynamic>.from(request.data as Map));
          handler.resolve(
              Response(requestOptions: request, data: {'notified': 0}));
        } else {
          handler.resolve(Response(requestOptions: request, data: <dynamic>[]));
        }
      }));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) async => null),
          myAddressesProvider.overrideWith((ref) async => []),
          selectedLocationProvider.overrideWith((ref) =>
              (lat: 12.97, lng: 77.59, address: 'Home, confirmed pin')),
          bookingRepositoryProvider.overrideWithValue(BookingRepository(dio)),
          workerRepositoryProvider.overrideWithValue(WorkerRepository(dio)),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [GxColors.dark]),
          home: const InstantRequestScreen(
              skill: 'Electrician', issueOptions: ['Switch repair']),
        )));
    await tester.pumpAndSettle();
    Future<void> tap(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await tap('Continue'); // Confirmed location.
    await tap('Continue'); // Customer is present.
    await tap('Switch repair');
    await tap('Continue');
    await tap('English');
    await tap('Continue');
    expect(sent, isEmpty);
    await tap('Review request');
    expect(find.text('Your offered rate: ₹250 / hour'), findsOneWidget);
    expect(find.text('Home, confirmed pin'), findsOneWidget);
    expect(sent, isEmpty);
    await tap('Confirm and find a professional');
    expect(sent, hasLength(1));
    expect(sent.single, containsPair('amount', 250.0));
    expect(sent.single, containsPair('description', 'Switch repair'));
    expect(sent.single, containsPair('preferredLanguages', ['English']));
    expect(find.text('No pros available right now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
