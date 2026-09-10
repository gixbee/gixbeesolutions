import 'package:flutter_test/flutter_test.dart';
import 'package:gixbee/repositories/auth_repository.dart';

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
}
