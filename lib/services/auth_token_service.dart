import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authTokenServiceProvider = Provider((ref) => AuthTokenService());

class AuthTokenService {
  final _storage = const FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  
  final _tokenController = StreamController<bool>.broadcast();

  AuthTokenService() {
    // Check initial state
    hasToken().then((exists) => _tokenController.add(exists));
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _tokenController.add(true);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
    _tokenController.add(false);
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Stream<bool> onTokenChange() => _tokenController.stream;
}
