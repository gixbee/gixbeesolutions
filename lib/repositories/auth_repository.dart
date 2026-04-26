import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../services/auth_token_service.dart';
import '../shared/models/user.dart';

// ── Dio provider ─────────────────────────────────────────────────────────────

final dioProvider = Provider((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: Duration(seconds: AppConfig.httpTimeoutSeconds),
    receiveTimeout: Duration(seconds: AppConfig.httpTimeoutSeconds),
  ));

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await ref.read(authTokenServiceProvider).getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    },
  ));

  return dio;
});

// ── Providers ─────────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider((ref) => AuthRepository(
      ref.watch(dioProvider),
      ref.watch(authTokenServiceProvider),
    ));

/// Auth gate — FutureProvider gives a definitive initial value on cold start.
/// No stream race condition, no loading flicker.
final authStateProvider = FutureProvider<bool>((ref) async {
  return ref.watch(authTokenServiceProvider).hasToken();
});

/// Currently logged-in user profile from the Gixbee backend.
final currentUserProvider = FutureProvider<User?>((ref) async {
  final hasToken = await ref.read(authTokenServiceProvider).hasToken();
  if (!hasToken) return null;
  return ref.read(authRepositoryProvider).getProfile();
});

// ── Repository ────────────────────────────────────────────────────────────────

class AuthRepository {
  final Dio _dio;
  final AuthTokenService _tokenService;
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;

  AuthRepository(this._dio, this._tokenService);

  // ── Supabase Phone OTP Flow ─────────────────────────────────

  /// Returns devOtp in DEBUG mode only — null in production.
  Future<String?> signInWithPhone(String phoneNumber) async {
    try {
      if (kDebugMode) debugPrint('[AUTH] Requesting OTP for $phoneNumber');
      await _supabase.auth.signInWithOtp(phone: phoneNumber);

      // Dev-only: backend may return a devOtp for local testing
      if (kDebugMode) {
        try {
          final res =
              await _dio.post('/auth/dev-otp', data: {'phone': phoneNumber});
          return res.data['devOtp'] as String?;
        } catch (_) {}
      }
      return null;
    } catch (e) {
      debugPrint('[AUTH] signInWithPhone failed: $e');
      rethrow;
    }
  }

  Future<void> verifyOtp({
    required String phoneNumber,
    required String token,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        phone: phoneNumber,
        token: token,
        type: sb.OtpType.sms,
      );

      if (response.session == null) {
        throw Exception('OTP verification failed — no session returned');
      }

      // Exchange Supabase session for Gixbee JWT
      final supabaseAccessToken = response.session!.accessToken;
      final gixbeeResponse = await _dio.post(
        '/auth/supabase-login',
        data: {'idToken': supabaseAccessToken},
      );

      final gixbeeToken = gixbeeResponse.data['accessToken'] as String?;
      if (gixbeeToken != null) {
        await _tokenService.saveToken(gixbeeToken);
      }
    } catch (e) {
      debugPrint('[AUTH] verifyOtp failed: $e');
      rethrow;
    }
  }

  // ── Profile ───────────────────────────────────────────────────

  Future<User?> getProfile() async {
    try {
      final response = await _dio.get('/auth/profile');
      return User.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[AUTH] getProfile failed: $e');
      return null;
    }
  }

  // ── FCM Token ──────────────────────────────────────────────────

  Future<void> registerFcmToken(String fcmToken) async {
    try {
      await _dio.patch('/auth/fcm-token', data: {'fcmToken': fcmToken});
      debugPrint('[AUTH] FCM token registered');
    } catch (e) {
      debugPrint('[AUTH] FCM token registration failed: $e');
      // Non-fatal — rethrow so caller can retry
      rethrow;
    }
  }

  // ── Sign Out ───────────────────────────────────────────────────

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _tokenService.deleteToken();
  }
}
