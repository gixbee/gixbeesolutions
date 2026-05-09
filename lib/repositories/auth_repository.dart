import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../services/auth_token_service.dart';
import '../shared/models/user.dart';

// ── Dio provider ─────────────────────────────────────────────────────────────

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: AppConfig.httpTimeoutSeconds),
    receiveTimeout: const Duration(seconds: AppConfig.httpTimeoutSeconds),
  ));

  final tokenService = ref.read(authTokenServiceProvider);

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final token = await tokenService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      return handler.next(options);
    },
    onError: (e, handler) async {
      if (e.response?.statusCode == 401 &&
          !e.requestOptions.path.contains('/auth/refresh') &&
          !e.requestOptions.path.contains('/auth/verify-otp')) {
        // Attempt silent token refresh
        debugPrint('[DIO] 401 — attempting token refresh');
        final refreshToken = await tokenService.getRefreshToken();

        if (refreshToken != null) {
          try {
            final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
            final response = await refreshDio.post(
              '/auth/refresh',
              data: {'refreshToken': refreshToken},
            );

            final newAccessToken = response.data['accessToken'] as String?;
            if (newAccessToken != null) {
              await tokenService.saveToken(newAccessToken);
              debugPrint('[DIO] Token refreshed — retrying original request');

              // Retry the original request with the new token
              final opts = e.requestOptions;
              opts.headers['Authorization'] = 'Bearer $newAccessToken';
              final retryResponse = await dio.fetch(opts);
              return handler.resolve(retryResponse);
            }
          } catch (refreshError) {
            debugPrint('[DIO] Token refresh failed: $refreshError');
          }
        }

        // Refresh failed — force logout
        debugPrint('[DIO] 401 Unauthorized — clearing tokens and forcing logout');
        await tokenService.deleteToken();
        ref.invalidate(authStateProvider);
      }
      return handler.next(e);
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

  AuthRepository(this._dio, this._tokenService);

  // ── Custom API OTP Flow ──────────────────────────────────────

  /// Requests an OTP from the Gixbee backend.
  /// Returns devOtp in DEBUG mode only — null in production.
  Future<String?> signInWithPhone(String phoneNumber) async {
    try {
      if (kDebugMode) debugPrint('[AUTH] Requesting OTP for $phoneNumber');
      final response = await _dio.post(
        '/auth/request-otp',
        data: {'phone': phoneNumber},
      );

      // Dev/test: backend returns devOtp for local testing
      return response.data['devOtp'] as String?;
    } catch (e) {
      debugPrint('[AUTH] signInWithPhone failed: $e');
      rethrow;
    }
  }

  /// Verifies the OTP with the Gixbee backend and saves both JWT tokens.
  Future<void> verifyOtp({
    required String phoneNumber,
    required String token,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/verify-otp',
        data: {'phone': phoneNumber, 'otp': token},
      );

      final accessToken = response.data['accessToken'] as String?;
      final refreshToken = response.data['refreshToken'] as String?;

      if (accessToken == null) {
        throw Exception('OTP verification failed — no accessToken returned');
      }
      await _tokenService.saveToken(accessToken);

      if (refreshToken != null) {
        await _tokenService.saveRefreshToken(refreshToken);
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
    await _tokenService.deleteToken();
  }
}
