import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authTokenServiceProvider = Provider((ref) => AuthTokenService());

class AuthTokenService {
  static const _accessKey = 'gixbee_auth_token';
  static const _refreshKey = 'gixbee_refresh_token';
  final _storage = const FlutterSecureStorage();

  // ── Access Token ──────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    await _storage.write(key: _accessKey, value: token);
  }

  Future<String?> getToken() async {
    try {
      return await _storage.read(key: _accessKey);
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
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  // ── Refresh Token ─────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    try {
      return await _storage.read(key: _refreshKey);
    } catch (e) {
      debugPrint('[AuthToken] getRefreshToken failed: $e');
      return null;
    }
  }
}
