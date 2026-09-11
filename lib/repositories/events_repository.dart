import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

const eventServices = <String, String>{
  'HALL': 'Hall', 'CATERING': 'Catering', 'DECORATION': 'Decor',
  'PHOTOGRAPHY': 'Photography', 'DJ': 'Music / DJ', 'MAKEUP': 'Makeup',
  'MEHENDI': 'Mehendi', 'INVITATIONS': 'Invitations',
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
        .map((v) => Map<String, dynamic>.from(v as Map)).toList();
  }

  Future<Map<String, dynamic>> detail(String id) async =>
      Map<String, dynamic>.from((await _dio.get('/events/$id')).data as Map);

  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from((await _dio.post('/events', data: data)).data as Map);

  Future<void> offer(String id, Map<String, dynamic> data) async {
    await _dio.post('/events/$id/quotes', data: data);
  }

  Future<void> action(String quoteId, String action,
      [Map<String, dynamic> data = const {}]) async {
    await _dio.post('/events/quotes/$quoteId/$action', data: data);
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
