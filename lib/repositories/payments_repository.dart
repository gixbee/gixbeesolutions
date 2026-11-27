import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

final paymentsRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return PaymentsRepository(dio);
});

class PaymentsRepository {
  final Dio _dio;

  PaymentsRepository(this._dio);

  Future<bool> confirmCapturedPayment(String? orderId, String? paymentId) async {
    if (orderId == null || paymentId == null) return false;
    try {
      final response = await _dio.post('/payments/orders/$orderId/verify',
          data: {'paymentId': paymentId});
      final data = response.data;
      return data is Map && data['status'] == 'CREDITED';
    } on DioException {
      // The durable webhook can still complete the order.
      return false;
    }
  }

  /// Direct Razorpay checkout for late-cancel travel compensation.
  /// `POST /payments/late-cancel-compensation/order` → {orderId, amount(paise),
  /// currency, keyId}. The webhook unblocks Instant Help on capture.
  Future<Map<String, dynamic>> createLateCancelCompensationOrder() async {
    try {
      final response =
          await _dio.post('/payments/late-cancel-compensation/order');
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      debugPrint('CreateLateCancelCompensationOrder failed: $e');
      rethrow;
    }
  }
}
