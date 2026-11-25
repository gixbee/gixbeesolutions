import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/events/event_service_catalogue_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/shared/models/business.dart';

void main() {
  const businessId = '47dba8e7-e7a7-44b0-b2ee-edc8d0840d14';

  test('decoration catalogue migration allows the decoration service type', () {
    final sql =
        File('scripts/event_catalogue_service_types.sql').readAsStringSync();
    expect(sql, contains("'DECORATION'"));
    expect(sql, contains("'PHOTOGRAPHY'"));
    expect(sql, contains("'CATERING'"));
    expect(sql, contains('event_service_catalogues_serviceType_check'));
  });

  testWidgets('catalogue settings put each label above its own field',
      (tester) async {
    tester.view.physicalSize = const Size(440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.path == '/events/catalogues/$businessId/DECORATION') {
        return handler.resolve(Response(requestOptions: options, data: {
          'revision': 1,
          'catalogue': {
            'about': '',
            'items': <Map<String, dynamic>>[],
            'photos': <String>[],
            'serviceCityIds': <String>[],
            'minNoticeDays': 0,
            'maxAdvanceDays': 730,
            'maxBookingsPerDay': 1,
          },
        }));
      }
      if (options.path == '/cities') {
        return handler.resolve(Response(requestOptions: options, data: [
          {
            'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            'name': 'Thiruvananthapuram',
            'state': 'Kerala',
            'lat': 8.52,
            'lng': 76.94,
            'isActive': true,
          },
        ]));
      }
      return handler.reject(DioException(
        requestOptions: options,
        message: 'Unexpected ${options.method} ${options.path}',
      ));
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        home: EventServiceCatalogueScreen(
          business: Business(
            id: businessId,
            name: 'Decor',
            type: 'SERVICE',
            serviceType: 'DECORATION',
            ownerId: 'owner',
            status: 'APPROVED',
          ),
          service: 'DECORATION',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Max bookings per day'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    for (final label in [
      'Minimum notice (days)',
      'Advance booking window (days)',
      'Max bookings per day',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final booking = fields.where(
      (field) => const {'0', '730', '1'}.contains(field.controller?.text),
    );
    expect(booking, hasLength(3));
    expect(
      booking.every((field) => field.decoration?.labelText == null),
      isTrue,
      reason: 'Booking labels must sit above the boxes, not on the numbers',
    );
    expect(find.text('730'), findsOneWidget);
    expect(find.text('Thiruvananthapuram, Kerala'), findsOneWidget);
  });
}
