import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../services/auth_token_service.dart';
import '../shared/models/user.dart';

// ── Dio provider with JWT interceptor ────────────────────────────────────────

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

// ── Providers ────────────────────────────────────────────────────────────────

final authRepositoryProvider = Provider((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(authTokenServiceProvider),
  );
});

/// Source of truth for "is user logged in" — driven by Supabase session.
final authStateProvider = StreamProvider<bool>((ref) {
  return sb.Supabase.instance.client.auth.onAuthStateChange.map((event) {
    return event.session != null;
  });
});

/// Currently logged-in user profile from the Gixbee backend.
final currentUserProvider = FutureProvider<User?>((ref) async {
  final hasToken = await ref.read(authTokenServiceProvider).hasToken();
  if (!hasToken) return null;
  return await ref.read(authRepositoryProvider).getProfile();
});

// ── Repository ───────────────────────────────────────────────────────────────

class AuthRepository {
  final Dio _dio;
  final AuthTokenService _tokenService;
  final sb.SupabaseClient _supabase = sb.Supabase.instance.client;

  AuthRepository(this._dio, this._tokenService);

  // ── Supabase Phone OTP Flow ──────────────────────────────

  Future<void> signInWithPhone(String phoneNumber) async {
    try {
      if (kDebugMode) {
        debugPrint('[AUTH] Requesting OTP for $phoneNumber');
      }
      await _supabase.auth.signInWithOtp(phone: phoneNumber);
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
      // 1. Verify OTP with Supabase
      final response = await _supabase.auth.verifyOTP(
        phone: phoneNumber,
        token: token,
        type: sb.OtpType.sms,
      );

      if (response.session == null) {
        throw Exception('OTP verification failed — no session returned');
      }

      // 2. Exchange Supabase session for Gixbee JWT
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
    await _supabase.auth.signOut();
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
