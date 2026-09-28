import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/auth_repository.dart';
import 'package:gixbee/shared/models/user.dart';

void main() {
  group('isPublicAuthPath', () {
    test('treats OTP and refresh as public so a 401 cannot reset the stack', () {
      expect(isPublicAuthPath('/auth/request-otp'), isTrue);
      expect(isPublicAuthPath('auth/request-otp'), isTrue);
      expect(isPublicAuthPath('/auth/verify-otp'), isTrue);
      expect(isPublicAuthPath('/auth/refresh'), isTrue);
      expect(isPublicAuthPath('/auth/admin-login'), isTrue);
    });

    test('keeps session APIs private so a real expiry still signs out', () {
      expect(isPublicAuthPath('/auth/fcm-token'), isFalse);
      expect(isPublicAuthPath('/auth/profile'), isFalse);
      expect(isPublicAuthPath('/bookings'), isFalse);
    });
  });

  group('authSessionIsGone', () {
    test('does not exit while auth is loading or refreshing after re-login', () {
      expect(authSessionIsGone(const AsyncLoading<bool>()), isFalse);
      final refreshing =
          const AsyncLoading<bool>().copyWithPrevious(const AsyncData(false));
      expect(refreshing.isRefreshing, isTrue);
      expect(authSessionIsGone(refreshing), isFalse);
    });

    test('exits only when JWT is known missing', () {
      expect(authSessionIsGone(const AsyncData(false)), isTrue);
      expect(authSessionIsGone(const AsyncData(true)), isFalse);
      expect(
        authSessionIsGone(const AsyncData(true), sessionExitStarted: true),
        isTrue,
      );
    });
  });

  group('shouldLeaveAppShell', () {
    const authed = AsyncData(true);
    const signedOut = AsyncData(false);

    test('does not bounce OTP while a null profile is still refreshing', () {
      expect(
        shouldLeaveAppShell(authed, const AsyncLoading<User?>()),
        isFalse,
      );
      final refreshing = const AsyncLoading<User?>()
          .copyWithPrevious(const AsyncData<User?>(null));
      expect(refreshing.isRefreshing, isTrue);
      expect(shouldLeaveAppShell(authed, refreshing), isFalse);
    });

    test('leaves the shell when the JWT is gone', () {
      expect(
        shouldLeaveAppShell(signedOut, const AsyncData<User?>(null)),
        isTrue,
      );
    });

    test('leaves the shell when a token is present but profile is nobody', () {
      // Profile "Session Expired" while Home still loaded.
      expect(
        shouldLeaveAppShell(authed, const AsyncData<User?>(null)),
        isTrue,
      );
    });

    test('leaves the shell on a settled /auth/profile 401', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/auth/profile'),
        response: Response(
          requestOptions: RequestOptions(path: '/auth/profile'),
          statusCode: 401,
        ),
      );
      expect(
        shouldLeaveAppShell(authed, AsyncError<User?>(err, StackTrace.empty)),
        isTrue,
      );
    });

    test('keeps the shell on a network error so Retry still works', () {
      expect(
        shouldLeaveAppShell(
          authed,
          AsyncError<User?>(Exception('timeout'), StackTrace.empty),
        ),
        isFalse,
      );
    });
  });
}
