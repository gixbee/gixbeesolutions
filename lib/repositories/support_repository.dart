import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(dioProvider));
});

/// General support channel (non-booking issues): file a ticket from
/// Help & Support, read your tickets + admin replies.
class SupportRepository {
  final Dio _dio;

  SupportRepository(this._dio);

  Future<void> createTicket({
    required String subject,
    required String message,
  }) async {
    await _dio.post('/support', data: {
      'subject': subject,
      'message': message,
    });
  }

  Future<List<Map<String, dynamic>>> myTickets() async {
    final res = await _dio.get('/support/my');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
