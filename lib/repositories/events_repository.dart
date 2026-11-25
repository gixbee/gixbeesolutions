import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

const eventServices = <String, String>{
  'HALL': 'Hall',
  'CATERING': 'Catering',
  'DECORATION': 'Decor',
  'PHOTOGRAPHY': 'Photography',
  'DJ': 'Music / DJ',
  'MAKEUP': 'Makeup',
  'MEHENDI': 'Mehendi',
  'INVITATIONS': 'Invitations',
};

final eventsRepositoryProvider = Provider<EventsRepository>(
  (ref) => EventsRepository(ref.watch(dioProvider)),
);

class EventsRepository {
  EventsRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> plans({String? businessId}) async {
    final response = await _dio.get(
      businessId == null ? '/events' : '/events/vendor/inbox',
      queryParameters: businessId == null ? null : {'businessId': businessId},
    );
    return (response.data as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  Future<Map<String, dynamic>> detail(String id) async =>
      Map<String, dynamic>.from((await _dio.get('/events/$id')).data as Map);

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
          (await _dio.post('/events', data: data)).data as Map);

  Future<List<Map<String, dynamic>>> discover(
    String service,
    String cityId,
  ) async {
    final response = await _dio.get(
      service == 'HALL' ? '/halls/discover' : '/events/catalogues',
      queryParameters: {
        'cityId': cityId,
        if (service != 'HALL') 'serviceType': service,
      },
    );
    return (response.data as List)
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  }

  Future<Map<String, dynamic>> hallDetails(String hallId, String day) async {
    final response = await _dio
        .get('/halls/$hallId/customer', queryParameters: {'day': day});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> catalogue(
      String businessId, String service) async {
    final response = await _dio.get('/events/catalogues/$businessId/$service');
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Confirmed photography bookings plus manually entered outside shoots.
  /// Server-side owner authorization is required for this endpoint.
  Future<List<Map<String, dynamic>>> photographyCalendar(
          String businessId) =>
      vendorCalendarOverview(businessId);

  /// Same owner schedule as [photographyCalendar]. Pass `CATERING` to load
  /// confirmed catering quotes instead of photography quotes. Outside
  /// bookings stay on the shared vendor calendar either way.
  Future<List<Map<String, dynamic>>> vendorCalendarOverview(
      String businessId, {String service = 'PHOTOGRAPHY'}) async {
    final response = await _dio.get(
      '/events/vendor/calendar/$businessId/overview',
      queryParameters:
          service == 'PHOTOGRAPHY' ? null : {'service': service},
    );
    return (response.data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> vendorCalendar(String businessId) async {
    final response = await _dio.get('/events/vendor/calendar/$businessId');
    return (response.data as List)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
  }

  Future<void> addCalendarBooking(
      String businessId, String title, DateTime start, DateTime end) async {
    await _dio.post('/events/vendor/calendar/$businessId', data: {
      'title': title,
      'startAt': start.toUtc().toIso8601String(),
      'endAt': end.toUtc().toIso8601String(),
    });
  }

  Future<void> updateCalendarBooking(
      String businessId, String id, String title,
      DateTime start, DateTime end) async {
    await _dio.put('/events/vendor/calendar/$businessId/$id', data: {
      'title': title,
      'startAt': start.toUtc().toIso8601String(),
      'endAt': end.toUtc().toIso8601String(),
    });
  }

  Future<void> cancelCalendarBooking(String businessId, String id) async {
    await _dio.delete('/events/vendor/calendar/$businessId/$id');
  }

  /// Marks or clears one civil day on the vendor interval calendar.
  /// The server stores an IST midnight-to-midnight row titled Unavailable.
  Future<void> setUnavailable(String businessId, DateTime date,
      {required bool blocked}) async {
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (blocked) {
      await _dio.post('/events/vendor/calendar/$businessId/unavailable',
          data: {'date': key});
    } else {
      await _dio.delete('/events/vendor/calendar/$businessId/unavailable',
          queryParameters: {'date': key});
    }
  }

  Future<Map<String, dynamic>> saveCatalogue(
    String businessId,
    String service,
    int revision,
    Map<String, dynamic> catalogue,
  ) async {
    final response = await _dio.put('/events/catalogues/$businessId/$service',
        data: {'revision': revision, 'catalogue': catalogue});
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> offer(String id, Map<String, dynamic> data) async {
    await _dio.post('/events/$id/quotes', data: data);
  }

  Future<void> action(String quoteId, String action,
      [Map<String, dynamic> data = const {}]) async {
    await _dio.post('/events/quotes/$quoteId/$action', data: data);
  }

  Future<List<Map<String, dynamic>>> quoteMilestones(String quoteId) async {
    final response = await _dio.get('/events/quotes/$quoteId/milestones');
    return (response.data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> createQuoteMilestones(
      String quoteId, List<Map<String, dynamic>> milestones) async {
    final response = await _dio.post(
      '/events/quotes/$quoteId/milestones',
      data: {'milestones': milestones},
    );
    return (response.data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> acknowledgeQuoteMilestone(
      String quoteId, String milestoneId) async {
    final response = await _dio.post(
      '/events/quotes/$quoteId/milestones/$milestoneId/ack',
      data: const {},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Private, authenticated photography delivery history (no public /uploads URL).
  Future<List<Map<String, dynamic>>> deliveryVersions(
      String quoteId, String milestoneId) async {
    final res = await _dio.get('/events/quotes/$quoteId/deliveries/$milestoneId');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> uploadDelivery(
      String quoteId, String milestoneId, String name,
      Uint8List content, String note) async {
    final res = await _dio.post(
      '/events/quotes/$quoteId/deliveries/$milestoneId',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(content, filename: name),
        'note': note,
      }),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Uint8List> downloadDelivery(String quoteId, String fileId) async {
    final response = await _dio.get<List<int>>(
      '/events/quotes/$quoteId/deliveries/file/$fileId',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> reviewDelivery(String quoteId, String milestoneId,
      String decision, String feedback) async {
    await _dio.post('/events/quotes/$quoteId/deliveries/$milestoneId/review',
      data: {'decision': decision, 'feedback': feedback});
  }

  Future<List<Map<String, dynamic>>> paymentReports(
      String quoteId, String milestoneId) async {
    final res = await _dio.get('/events/quotes/$quoteId/payments/$milestoneId');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> paymentEvidence(
      String quoteId, String milestoneId) async {
    final res = await _dio.get(
      '/events/quotes/$quoteId/payments/$milestoneId/evidence');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> uploadPaymentEvidence(String quoteId, String milestoneId,
      String fileName, Uint8List content) async {
    await _dio.post('/events/quotes/$quoteId/payments/$milestoneId/evidence',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(content, filename: fileName),
      }));
  }

  Future<Uint8List> downloadPaymentEvidence(String quoteId, String fileId) async {
    final response = await _dio.get<List<int>>(
      '/events/quotes/$quoteId/payments/evidence/$fileId',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> reportDirectPayment(String quoteId, String milestoneId,
      {required String method, required String reference,
       required String note}) async {
    await _dio.post('/events/quotes/$quoteId/payments/$milestoneId',
      data: {'method': method, 'reference': reference, 'note': note});
  }

  Future<void> reviewDirectPayment(String quoteId, String milestoneId,
      String decision, String note) async {
    await _dio.post('/events/quotes/$quoteId/payments/$milestoneId/review',
      data: {'decision': decision, 'note': note});
  }

  Future<List<Map<String, dynamic>>> quoteDisputes(String quoteId) async {
    final res = await _dio.get('/events/quotes/$quoteId/disputes');
    return (res.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> openQuoteDispute(String quoteId, String milestoneId,
      String reason) async {
    await _dio.post('/events/quotes/$quoteId/disputes',
      data: {'milestoneId': milestoneId, 'reason': reason});
  }

  Future<void> disputeMessage(String quoteId, String disputeId,
      String message) async {
    await _dio.post('/events/quotes/$quoteId/disputes/$disputeId/message',
      data: {'message': message});
  }

  Future<void> resolveQuoteDispute(String quoteId, String disputeId,
      String resolution, String note) async {
    await _dio.post('/events/quotes/$quoteId/disputes/$disputeId/resolve',
      data: {'resolution': resolution, 'note': note});
  }

  Future<void> cancel(String id) async {
    await _dio.post('/events/$id/cancel');
  }
}

String eventError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'] ?? data['error'];
      if (message is String) return message;
    }
  }
  return 'Unable to save or load this event. Please try again.';
}

String eventDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date unavailable';
  return '${date.day}/${date.month}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String eventMoney(dynamic value) =>
    '₹${(num.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(2)}';
