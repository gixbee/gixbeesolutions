import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final authTokenServiceProvider = Provider((ref) => AuthTokenService());

class AuthTokenService {
  static const _accessKey = 'gixbee_auth_token';
  static const _refreshKey = 'gixbee_refresh_token';
  final _storage = const FlutterSecureStorage();
  
  String? _cachedAccessToken;
  String? _cachedRefreshToken;
  bool _hasReadAccess = false;
  bool _hasReadRefresh = false;

  // ── Access Token ──────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    _cachedAccessToken = token;
    _hasReadAccess = true;
    await _storage.write(key: _accessKey, value: token);
  }

  Future<String?> getToken() async {
    if (_hasReadAccess) return _cachedAccessToken;
    try {
      _cachedAccessToken = await _storage.read(key: _accessKey);
      _hasReadAccess = true;
      return _cachedAccessToken;
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
    // Mark caches as read *before* touching disk so a concurrent getToken()
    // cannot reload the old JWT from storage and resurrect the session.
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    _hasReadAccess = true;
    _hasReadRefresh = true;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  // ── Refresh Token ─────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async {
    _cachedRefreshToken = token;
    _hasReadRefresh = true;
    await _storage.write(key: _refreshKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    if (_hasReadRefresh) return _cachedRefreshToken;
    try {
      _cachedRefreshToken = await _storage.read(key: _refreshKey);
      _hasReadRefresh = true;
      return _cachedRefreshToken;
    } catch (e) {
      debugPrint('[AuthToken] getRefreshToken failed: $e');
      return null;
    }
  }
}
