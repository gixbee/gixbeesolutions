import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/models/business.dart';
import 'auth_repository.dart';

final businessRepositoryProvider = Provider<BusinessRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return BusinessRepository(dio);
});

class BusinessRepository {
  final Dio _dio;

  BusinessRepository(this._dio);

  Future<Business> registerBusiness(Business business) async {
    final res = await _dio.post('/businesses', data: business.toJson());
    return Business.fromJson(res.data);
  }

  Future<List<Business>> getMyBusinesses() async {
    final res = await _dio.get('/businesses/my');
    return (res.data as List).map((json) => Business.fromJson(json)).toList();
  }

  Future<void> addOperator(String businessId, String userId, String role) async {
    await _dio.post('/businesses/$businessId/operators', data: {'userId': userId, 'role': role});
  }

  Future<void> initiateOwnershipTransfer(String businessId, String newOwnerId) async {
    await _dio.post('/businesses/$businessId/transfer', data: {'newOwnerId': newOwnerId});
  }

  Future<void> addOfflineDay(String businessId, DateTime date) async {
    await _dio.post('/businesses/$businessId/calendar/offline', data: {'date': date.toIso8601String()});
  }
}
