import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authTokenServiceProvider = Provider((ref) => AuthTokenService());

class AuthTokenService {
  static const _key = 'gixbee_auth_token';
  final _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: _key, value: token);
  }

  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      debugPrint('[AuthToken] getToken failed: $e');
      return null;
    }
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _key);
  }
}
