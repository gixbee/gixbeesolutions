import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/features/hall_owner/hall_enquiries_inbox_screen.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/shared/models/business.dart';

void main() {
  const businessId = '47dba8e7-e7a7-44b0-b2ee-edc8d0840d14';
  const enquiryId = 'b08b0b52-57c4-48d1-b84d-20ac2f0837c2';
  const hallId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const planId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  testWidgets('reassign shows the server booking conflict, not a raw network dump',
      (tester) async {
    tester.view.physicalSize = const Size(440, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'GET' &&
          options.path == '/businesses/$businessId/hall-enquiries') {
        return handler.resolve(Response(requestOptions: options, data: [
          {
            'id': enquiryId,
            'status': 'ASSIGNED',
            'eventType': 'Wedding',
            'eventPlanId': planId,
            'assignedHallId': hallId,
            'requestedHallId': hallId,
            'hallName': 'sunadra',
            'requestedHallName': 'sunadra',
            'startTime': '2026-12-15T03:30:00.000Z',
            'endTime': '2026-12-15T08:30:00.000Z',
            'guestCount': 100,
            'venueTimezone': 'Asia/Kolkata',
            'readOnly': false,
          },
        ]));
      }
      if (options.method == 'GET' &&
          options.path == '/businesses/$businessId/halls') {
        return handler.resolve(Response(requestOptions: options, data: [
          {'id': hallId, 'name': 'sunadra', 'packageSaved': true},
        ]));
      }
      if (options.method == 'POST' &&
          options.path ==
              '/businesses/$businessId/hall-enquiries/$enquiryId/assign-hall') {
        return handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {
              'message':
                  'This hall already has a booking or hold in that time window',
            },
          ),
        ));
      }
      return handler.reject(DioException(
        requestOptions: options,
        message: 'Unexpected ${options.method} ${options.path}',
      ));
    }));

    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        home: HallEnquiriesInboxScreen(
          business: Business(
            id: businessId,
            name: 'Venue',
            type: 'SERVICE',
            serviceType: 'HALL',
            ownerId: 'owner',
            status: 'APPROVED',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hall assigned'), findsOneWidget);
    expect(find.textContaining('2026-12-15T'), findsNothing);

    await tester.tap(find.text('Reassign hall'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'sunadra'));
    await tester.pumpAndSettle();

    expect(
      find.text(
          'This hall already has a booking or hold in that time window'),
      findsOneWidget,
    );
    expect(find.textContaining('DioException'), findsNothing);
  });
}
