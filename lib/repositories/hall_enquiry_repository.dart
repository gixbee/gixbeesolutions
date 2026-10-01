import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final hallEnquiryRepositoryProvider = Provider<HallEnquiryRepository>((ref) {
  return HallEnquiryRepository(ref.watch(dioProvider));
});

class HallEnquiryRepository {
  HallEnquiryRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> listBusiness(String businessId) async {
    final res = await _dio.get('/businesses/$businessId/hall-enquiries');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> listForHall(
    String businessId,
    String hallId,
  ) async {
    final res =
        await _dio.get('/businesses/$businessId/halls/$hallId/enquiries');
    return (res.data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> approve(String businessId, String enquiryId) async {
    await _dio.post(
      '/businesses/$businessId/hall-enquiries/$enquiryId/owner-approve',
    );
  }

  Future<void> decline(String businessId, String enquiryId) async {
    await _dio.post(
      '/businesses/$businessId/hall-enquiries/$enquiryId/owner-decline',
    );
  }

  Future<Map<String, dynamic>> assignHall({
    required String businessId,
    required String enquiryId,
    required String hallId,
    required DateTime proposedStart,
    required DateTime proposedEnd,
  }) async {
    final res = await _dio.post(
      '/businesses/$businessId/hall-enquiries/$enquiryId/assign-hall',
      data: {
        'hallId': hallId,
        'proposedStartAt': proposedStart.toUtc().toIso8601String(),
        'proposedEndAt': proposedEnd.toUtc().toIso8601String(),
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }
}
