import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/core/config/app_config.dart';

void main() {
  group('AppConfig.isLoopbackUrl', () {
    test('flags localhost / 127.0.0.1 / emulator bridge', () {
      expect(AppConfig.isLoopbackUrl('http://127.0.0.1:3000'), isTrue);
      expect(AppConfig.isLoopbackUrl('http://localhost:3000'), isTrue);
      expect(AppConfig.isLoopbackUrl('http://0.0.0.0:3000'), isTrue);
      expect(AppConfig.isLoopbackUrl('http://10.0.2.2:3000'), isTrue);
      expect(AppConfig.isLoopbackUrl('http://[::1]:3000'), isTrue);
    });

    test('allows real hosts', () {
      expect(
        AppConfig.isLoopbackUrl('http://13.233.60.215:3000'),
        isFalse,
      );
      expect(AppConfig.isLoopbackUrl('https://api.gixbee.com'), isFalse);
    });

    test('treats empty / invalid as unsafe', () {
      expect(AppConfig.isLoopbackUrl(''), isTrue);
      expect(AppConfig.isLoopbackUrl('not a url'), isTrue);
    });
  });

  group('AppConfig.isCleartextUrl', () {
    test('flags http and allows https', () {
      expect(AppConfig.isCleartextUrl('http://api.example.com'), isTrue);
      expect(AppConfig.isCleartextUrl('https://api.example.com'), isFalse);
    });
  });

  group('AppConfig.assertReleaseNetworkConfig', () {
    test('no-ops in non-release mode even with loopback defaults', () {
      expect(
        () => AppConfig.assertReleaseNetworkConfig(isRelease: false),
        returnsNormally,
      );
    });

    test('throws in release mode when defaults are loopback', () {
      // Without dart-defines, baseUrl/socketUrl are 127.0.0.1 / localhost.
      expect(
        () => AppConfig.assertReleaseNetworkConfig(isRelease: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('loopback'),
          ),
        ),
      );
    });

    test('release boot does not refuse solely for placeholder Razorpay', () {
      // Loopback still throws first in this suite (no dart-defines). The
      // Razorpay placeholder alone must not be a boot killer — that left
      // release APKs on a black screen when RAZORPAY_KEY was unset.
      expect(
        () => AppConfig.assertReleaseNetworkConfig(isRelease: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            isNot(contains('RAZORPAY_KEY')),
          ),
        ),
      );
    });
  });
}
