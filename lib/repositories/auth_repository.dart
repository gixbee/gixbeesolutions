import 'package:dio/dio.dart';
// Removed Supabase dependency
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../services/auth_token_service.dart';
import '../shared/models/user.dart';

// ── Dio provider with JWT interceptor ────────────────────────────────────────

final dioProvider = Provider((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: AppConfig.httpTimeoutSeconds),
    receiveTimeout: const Duration(seconds: AppConfig.httpTimeoutSeconds),
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

// ── Providers ────────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(authTokenServiceProvider),
  );
});

/// Source of truth for "is user logged in" — driven by token presence.
final authStateProvider = StreamProvider<bool>((ref) {
  return ref.watch(authTokenServiceProvider).onTokenChange();
});

/// Currently logged-in user profile from the Gixbee backend.
final currentUserProvider = FutureProvider<User?>((ref) async {
  final isAuthenticated = ref.watch(authStateProvider).value ?? false;
  if (!isAuthenticated) return null;
  return await ref.read(authRepositoryProvider).getProfile();
});

// ── Repository ───────────────────────────────────────────────────────────────

class AuthRepository {
  final Dio _dio;
  final AuthTokenService _tokenService;

  AuthRepository(this._dio, this._tokenService);

  // ── Gixbee API OTP Flow ──────────────────────────────

  Future<String?> signInWithPhone(String phoneNumber) async {
    try {
      if (kDebugMode) {
        debugPrint('[AUTH] Requesting OTP for $phoneNumber via Gixbee API');
      }
      final response = await _dio.post('/auth/request-otp', data: {'phone': phoneNumber});
      return response.data['devOtp'] as String?;
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
      if (kDebugMode) {
        debugPrint('[AUTH] Verifying OTP for $phoneNumber via Gixbee API');
      }
      
      // 1. Verify OTP with Gixbee Backend
      final response = await _dio.post(
        '/auth/verify-otp',
        data: {'phone': phoneNumber, 'otp': token},
      );

      final gixbeeToken = response.data['accessToken'] as String?;
      if (gixbeeToken != null) {
        await _tokenService.saveToken(gixbeeToken);
      } else {
        throw Exception('OTP verification failed — no token returned');
      }
    } catch (e) {
      debugPrint('[AUTH] verifyOtp failed: $e');
      rethrow;
    }
  }

  // ── Profile ──────────────────────────────────────────────

  Future<User?> getProfile() async {
    try {
      final response = await _dio.get('/auth/profile');
      return User.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[AUTH] getProfile failed: $e');
      return null;
    }
  }

  // ── FCM Token ─────────────────────────────────────────────
  // Registers this device's FCM token so NestJS can send push notifications.
  // Called after OTP verification and on token refresh.

  Future<void> registerFcmToken(String fcmToken) async {
    try {
      await _dio.patch('/auth/fcm-token', data: {'fcmToken': fcmToken});
      debugPrint('[AUTH] FCM token registered');
    } catch (e) {
      // Non-fatal — log and continue
      debugPrint('[AUTH] FCM token registration failed: $e');
    }
  }

  // ── Sign Out ──────────────────────────────────────────────

  Future<void> signOut() async {
    await _tokenService.deleteToken();
  }

  // ── Legacy Password Auth (kept for compatibility) ─────────

  Future<void> signUp({
    required String phone,
    required String password,
  }) async {
    try {
      await _dio.post('/auth/register', data: {
        'phone': phone,
        'password': password,
      });
    } catch (e) {
      debugPrint('[AUTH] signUp failed: $e');
      rethrow;
    }
  }

  Future<void> signIn({
    required String phone,
    required String password,
  }) async {
    try {
      final response = await _dio.post('/auth/login', data: {
        'phone': phone,
        'password': password,
      });
      final token = response.data['accessToken'] as String?;
      if (token != null) await _tokenService.saveToken(token);
    } catch (e) {
      debugPrint('[AUTH] signIn failed: $e');
      rethrow;
    }
  }
}
