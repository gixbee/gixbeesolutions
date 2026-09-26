import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../core/navigator_key.dart';
import '../features/onboarding/welcome_screen.dart';
import '../services/app_data_cache.dart';
import '../services/auth_token_service.dart';
import '../services/socket_service.dart';
import '../shared/models/user.dart';
import '../features/worker/worker_instant_eligibility.dart';
import 'worker_repository.dart';

/// OTP / refresh / admin-login are public. A leftover Bearer token must not
/// trigger silent refresh or a stack reset back to Welcome.
@visibleForTesting
bool isPublicAuthPath(String path) {
  final p = path.toLowerCase();
  return p.contains('auth/request-otp') ||
      p.contains('auth/verify-otp') ||
      p.contains('auth/refresh') ||
      p.contains('auth/admin-login');
}

/// True when the JWT is known missing (or teardown already started).
///
/// After Sign Out, [currentUserProvider] stays `AsyncData(null)`. Re-login
/// invalidates it, but the previous null can still be visible for a frame.
/// Treating that as logged-out bounces OTP back to "Continue with phone".
/// Use [shouldLeaveAppShell] for the real gate — JWT gone *or* profile 401.
@visibleForTesting
bool authSessionIsGone(AsyncValue<bool> auth, {bool sessionExitStarted = false}) {
  if (sessionExitStarted) return true;
  if (auth.isLoading || auth.isRefreshing) return false;
  return auth.asData?.value == false;
}

bool _isUnauthorized(Object? error) =>
    error is DioException && error.response?.statusCode == 401;

/// True when the logged-in shell must go to Welcome.
///
/// A missing JWT is sign-out. A settled null profile or 401 *while a token
/// is still marked present* is expiry — Profile used to paint
/// "Session Expired" in-tab and leave Home / Bookings / Messages usable.
///
/// Loading or refreshing profile must not count: after OTP we invalidate
/// [currentUserProvider] and the previous `AsyncData(null)` is still
/// visible with [AsyncValue.isRefreshing] until `/auth/profile` returns.
@visibleForTesting
bool shouldLeaveAppShell(
  AsyncValue<bool> auth,
  AsyncValue<User?> user, {
  bool sessionExitStarted = false,
}) {
  if (authSessionIsGone(auth, sessionExitStarted: sessionExitStarted)) {
    return true;
  }
  if (auth.isLoading || auth.isRefreshing) return false;
  if (user.isLoading || user.isRefreshing) return false;
  if (auth.asData?.value != true) return false;
  if (user.hasError) return _isUnauthorized(user.error);
  return user.hasValue && user.value == null;
}

Completer<void>? _logoutGate;

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
      if (isPublicAuthPath(options.path) ||
          isPublicAuthPath(options.uri.path)) {
        options.headers.remove('Authorization');
        return handler.next(options);
      }
      final token = await tokenService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      // Remember which token this request was signed with so a late 401 from a
      // previous session cannot tear down a session that has since re-logged in.
      options.extra['authToken'] = token;
      return handler.next(options);
    },
    onError: (e, handler) async {
      final path = e.requestOptions.path;
      final uriPath = e.requestOptions.uri.path;
      if (e.response?.statusCode == 401 &&
          !isPublicAuthPath(path) &&
          !isPublicAuthPath(uriPath)) {
        // Stale-session guard: if the current stored token differs from the one
        // this request used, a new login already replaced it (e.g. logout →
        // re-login). Ignore this late 401 so we don't wipe the fresh session.
        final currentToken = await tokenService.getToken();
        final usedToken = e.requestOptions.extra['authToken'] as String?;
        if (currentToken == null || usedToken != currentToken) {
          debugPrint('[DIO] Ignoring stale 401 from a previous session');
          if (currentToken == null) {
            // Token already cleared — do not leave authState stuck true
            // so Home / bottom nav stay usable after Profile 401.
            ref.invalidate(authStateProvider);
          }
          return handler.next(e);
        }
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
              try {
                ref
                    .read(socketServiceProvider)
                    .reconnectWithToken(newAccessToken);
              } catch (_) {}

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

        // Refresh failed — force logout (clears shell + tokens).
        debugPrint('[DIO] 401 Unauthorized — clearing tokens and forcing logout');
        await forceLogoutToWelcome(ref);
      }
      return handler.next(e);
    },
  ));

  return dio;
});

/// Clear tokens, invalidate auth providers, and replace the nav stack with
/// Welcome. Safe to call from interceptors and UI (idempotent).
Future<void> forceLogoutToWelcome(Ref ref) => _forceLogoutToWelcome(
      ref.read(socketServiceProvider),
      ref.read(authTokenServiceProvider),
      () {
        clearWorkerAvailabilitySessionState(ref);
        ref.invalidate(authStateProvider);
        ref.invalidate(currentUserProvider);
      },
    );

/// Same teardown from a widget. `WidgetRef` and `Ref` share no supertype, so
/// sign-out buttons need their own entry point instead of a second copy of the
/// teardown.
Future<void> forceLogoutToWelcomeFromWidget(WidgetRef ref) =>
    _forceLogoutToWelcome(
      ref.read(socketServiceProvider),
      ref.read(authTokenServiceProvider),
      () {
        clearWorkerAvailabilitySessionStateWidget(ref);
        ref.invalidate(authStateProvider);
        ref.invalidate(currentUserProvider);
      },
    );

Future<void> _forceLogoutToWelcome(
  SocketService socketService,
  AuthTokenService tokenService,
  void Function() invalidateSession,
) async {
  if (_logoutGate != null) {
    await _logoutGate!.future;
    return;
  }
  final gate = Completer<void>();
  _logoutGate = gate;
  try {
    try {
      socketService.disconnect();
    } catch (_) {}
    // Late 401s (FCM, polls) after the user already signed out must not
    // pushAndRemoveUntil(Welcome) — that wipes Login → OTP.
    final hadToken = await tokenService.hasToken();
    await tokenService.deleteToken();
    AppDataCache.instance.clearAll();
    invalidateSession();
    if (!hadToken) return;
    final nav = rootNavigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  } finally {
    if (!gate.isCompleted) gate.complete();
    if (identical(_logoutGate, gate)) _logoutGate = null;
  }
}

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
  // 401 is not swallowed as null — that painted Profile "Session Expired"
  // while the interceptor/shell still treated the JWT as a live session.
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
      if (kDebugMode) {
        debugPrint('[AUTH] Requesting OTP for $phoneNumber');
        debugPrint('[AUTH] Base URL is: ${AppConfig.baseUrl}');
      }
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

  /// Confirms an OTP for a business phone without swapping the session.
  Future<void> confirmOtp({
    required String phoneNumber,
    required String token,
  }) async {
    await _dio.post(
      '/auth/confirm-otp',
      data: {'phone': phoneNumber, 'otp': token},
    );
  }

  // ── Profile ───────────────────────────────────────────────────

  Future<User?> getProfile() async {
    try {
      final response = await _dio.get('/auth/profile');
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      // Never swallow failures as a null user — that painted "Session Expired"
      // while the shell (bottom nav) stayed up. 401 → interceptor logout;
      // other errors stay as errors so the shell is not torn down.
      debugPrint('[AUTH] getProfile failed: $e');
      rethrow;
    } catch (e) {
      debugPrint('[AUTH] getProfile failed: $e');
      rethrow;
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
