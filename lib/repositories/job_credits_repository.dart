import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final jobCreditsRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return JobCreditsRepository(dio);
});

class JobCreditsRepository {
  final Dio _dio;

  JobCreditsRepository(this._dio);

  Future<int> getBalance() async {
    try {
      final response = await _dio.get('/billing/credits/balance');
      return response.data['balance'] as int;
    } catch (e) {
      debugPrint('JobCredits getBalance failed: $e');
      return 0;
    }
  }

  /// Credit + debit history, newest first. Each row: {id, delta, reason,
  /// bookingId, bookingSkill, createdAt}.
  Future<List<Map<String, dynamic>>> getTransactions({int page = 1}) async {
    final response = await _dio.get(
      '/billing/credits/transactions',
      queryParameters: {'page': page},
    );
    final list = response.data['transactions'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> getPackInfo() async {
    try {
      final response = await _dio.get('/billing/credits/pack-info');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('JobCredits getPackInfo failed: $e');
      return {'credits': 3, 'price': 49, 'currency': 'INR'};
    }
  }

  Future<Map<String, dynamic>> createOrder() async {
    final response = await _dio.post('/billing/credits/create-order');
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<int> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    final response = await _dio.post(
      '/billing/credits/verify',
      data: {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      },
    );
    return response.data['balance'] as int;
  }
}
