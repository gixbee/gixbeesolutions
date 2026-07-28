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

  // ── RAZORPAY RECHARGE ──

  /// Step 1 of a wallet recharge: the SERVER creates the Razorpay order.
  /// `POST /payments/recharge/order` → {orderId, amount(paise), currency,
  /// keyId}. Checkout must be opened with this orderId; crediting happens
  /// exclusively via the signature-verified Razorpay webhook — the app
  /// never confirms payments itself.
  Future<Map<String, dynamic>> createRechargeOrder(double amount) async {
    final response = await _dio.post(
      '/payments/recharge/order',
      data: {'amount': amount},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
