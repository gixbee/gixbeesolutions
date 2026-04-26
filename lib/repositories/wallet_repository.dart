import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final walletRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return WalletRepository(dio);
});

class WalletRepository {
  final Dio _dio;

  WalletRepository(this._dio);

  Future<double> getBalance() async {
    try {
      final response = await _dio.get('/wallets/balance');
      final balance = response.data['balance'];
      return (num.tryParse(balance.toString()) ?? 0).toDouble();
    } catch (e) {
      debugPrint('GetBalance failed: $e');
      return 0.0;
    }
  }

  Future<List<dynamic>> getTransactions() async {
    try {
      final response = await _dio.get('/wallets/transactions');
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint('GetTransactions failed: $e');
      return [];
    }
  }

  // ── PAYMENT VERIFICATION ──

  Future<void> verifyPayment({
    required String paymentId,
    String? orderId,
    String? signature,
  }) async {
    try {
      await _dio.post('/wallets/verify-payment', data: {
        'paymentId': paymentId,
        'orderId': orderId,
        'signature': signature,
      });
    } catch (e) {
      debugPrint('VerifyAndCredit failed: $e');
      rethrow;
    }
  }
}
