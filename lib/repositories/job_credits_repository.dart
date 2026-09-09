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

  Future<Map<String, dynamic>> getBookingCreditUsage(String bookingId) async {
    try {
      final response = await _dio.get('/billing/credits/booking/$bookingId');
      return Map<String, dynamic>.from(response.data as Map);
    } catch (e) {
      debugPrint('JobCredits getBookingCreditUsage failed: $e');
      return {'creditsUsed': 0, 'creditsRefunded': 0};
    }
  }

  Future<int> getBalance() async {
    final info = await getBalanceInfo();
    return info.balance;
  }

  /// Balance plus Master Entries accept cost (`job_credit_per_accept`).
  Future<({int balance, int creditsPerAccept})> getBalanceInfo() async {
    try {
      final response = await _dio.get('/billing/credits/balance');
      final data = response.data as Map;
      return (
        balance: (data['balance'] as num?)?.toInt() ?? 0,
        creditsPerAccept: (data['creditsPerAccept'] as num?)?.toInt() ?? 15,
      );
    } catch (e) {
      debugPrint('JobCredits getBalanceInfo failed: $e');
      rethrow;
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
    final response = await _dio.get('/billing/credits/pack-info');
    final pack = Map<String, dynamic>.from(response.data as Map);
    final credits = pack['credits'];
    final cost = pack['creditsPerAccept'];
    final price = pack['price'];
    if (credits is! num ||
        cost is! num ||
        price is! num ||
        !credits.isFinite ||
        !cost.isFinite ||
        !price.isFinite ||
        credits < 0 ||
        cost < 0 ||
        price <= 0 ||
        credits != credits.toInt() ||
        cost != cost.toInt() ||
        (cost > 0 && credits < cost) ||
        pack['currency'] != 'INR') {
      throw const FormatException('Credit pack details are unavailable.');
    }
    return pack;
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
