import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_repository.dart';

final paymentRepositoryProvider = Provider((ref) {
  final dio = ref.watch(dioProvider);
  return PaymentRepository(dio);
});

/// Gateway readiness as reported by `GET /payments/gateway-status`.
/// UPI/PhonePe stays in a "setup pending" state until the merchant
/// API key is configured server-side.
class GatewayStatus {
  final bool upiAvailable;
  final bool upiNeedsApiKey;
  final String? upiMessage;

  const GatewayStatus({
    required this.upiAvailable,
    required this.upiNeedsApiKey,
    this.upiMessage,
  });

  /// Safe default when the status call fails: treat UPI as not yet live.
  static const unavailable = GatewayStatus(
    upiAvailable: false,
    upiNeedsApiKey: true,
    upiMessage: 'UPI gateway status unavailable',
  );

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    final upi = (json['upi'] as Map?)?.cast<String, dynamic>() ?? const {};
    return GatewayStatus(
      upiAvailable: upi['available'] == true,
      upiNeedsApiKey: upi['needsApiKey'] == true,
      upiMessage: upi['message'] as String?,
    );
  }
}

/// Auto-disposing provider so the picker always reflects current gateway state.
final gatewayStatusProvider = FutureProvider.autoDispose<GatewayStatus>(
  (ref) => ref.watch(paymentRepositoryProvider).getGatewayStatus(),
);

class PaymentRepository {
  final Dio _dio;

  PaymentRepository(this._dio);

  Future<GatewayStatus> getGatewayStatus() async {
    try {
      final response = await _dio.get('/payments/gateway-status');
      return GatewayStatus.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } catch (e) {
      debugPrint('GetGatewayStatus failed: $e');
      return GatewayStatus.unavailable;
    }
  }

  /// Initiates a UPI payment. While the PhonePe merchant key is missing the
  /// backend returns `{status: UNAVAILABLE, needsApiKey: true, message}` —
  /// callers must surface that state instead of treating it as success.
  // TODO: needs PhonePe API key — flow goes live once the backend is configured.
  Future<Map<String, dynamic>> initiateUpiPayment({
    required double amount,
    String? bookingId,
  }) async {
    final response = await _dio.post('/payments/upi/initiate', data: {
      'amount': amount,
      if (bookingId != null) 'bookingId': bookingId,
    });
    return (response.data as Map).cast<String, dynamic>();
  }
}
