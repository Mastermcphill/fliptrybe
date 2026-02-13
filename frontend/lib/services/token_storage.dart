import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userMode,
    required this.lastLoginAt,
    required this.tokenExpiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String userMode;
  final String lastLoginAt;
  final String tokenExpiresAt;
}

class TokenStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userModeKey = 'user_mode';
  static const _lastLoginAtKey = 'last_login_at';
  static const _tokenExpiresAtKey = 'token_expires_at';
  static const _secure = FlutterSecureStorage();

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    String? userMode,
    String? lastLoginAt,
    String? tokenExpiresAt,
  }) async {
    final at = accessToken.trim();
    final rt = (refreshToken ?? '').trim();
    final mode = (userMode ?? '').trim();
    final loginAt = (lastLoginAt ?? '').trim();
    final expiresAt = (tokenExpiresAt ?? '').trim();

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessTokenKey, at);
      if (rt.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, rt);
      } else {
        await prefs.remove(_refreshTokenKey);
      }
      if (mode.isNotEmpty) {
        await prefs.setString(_userModeKey, mode);
      } else {
        await prefs.remove(_userModeKey);
      }
      if (loginAt.isNotEmpty) {
        await prefs.setString(_lastLoginAtKey, loginAt);
      } else {
        await prefs.remove(_lastLoginAtKey);
      }
      if (expiresAt.isNotEmpty) {
        await prefs.setString(_tokenExpiresAtKey, expiresAt);
      } else {
        await prefs.remove(_tokenExpiresAtKey);
      }
      return;
    }

    await _secure.write(key: _accessTokenKey, value: at);
    if (rt.isNotEmpty) {
      await _secure.write(key: _refreshTokenKey, value: rt);
    } else {
      await _secure.delete(key: _refreshTokenKey);
    }
    if (mode.isNotEmpty) {
      await _secure.write(key: _userModeKey, value: mode);
    } else {
      await _secure.delete(key: _userModeKey);
    }
    if (loginAt.isNotEmpty) {
      await _secure.write(key: _lastLoginAtKey, value: loginAt);
    } else {
      await _secure.delete(key: _lastLoginAtKey);
    }
    if (expiresAt.isNotEmpty) {
      await _secure.write(key: _tokenExpiresAtKey, value: expiresAt);
    } else {
      await _secure.delete(key: _tokenExpiresAtKey);
    }
  }

  Future<void> saveToken(String token) async {
    await saveSession(accessToken: token);
  }

  Future<String?> readToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_accessTokenKey);
    }
    return _secure.read(key: _accessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenKey);
    }
    return _secure.read(key: _refreshTokenKey);
  }

  Future<StoredSession> readSession() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return StoredSession(
        accessToken: (prefs.getString(_accessTokenKey) ?? '').trim(),
        refreshToken: (prefs.getString(_refreshTokenKey) ?? '').trim(),
        userMode: (prefs.getString(_userModeKey) ?? '').trim(),
        lastLoginAt: (prefs.getString(_lastLoginAtKey) ?? '').trim(),
        tokenExpiresAt: (prefs.getString(_tokenExpiresAtKey) ?? '').trim(),
      );
    }
    return StoredSession(
      accessToken: ((await _secure.read(key: _accessTokenKey)) ?? '').trim(),
      refreshToken: ((await _secure.read(key: _refreshTokenKey)) ?? '').trim(),
      userMode: ((await _secure.read(key: _userModeKey)) ?? '').trim(),
      lastLoginAt: ((await _secure.read(key: _lastLoginAtKey)) ?? '').trim(),
      tokenExpiresAt: ((await _secure.read(key: _tokenExpiresAtKey)) ?? '').trim(),
    );
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_userModeKey);
      await prefs.remove(_lastLoginAtKey);
      await prefs.remove(_tokenExpiresAtKey);
      return;
    }
    await _secure.delete(key: _accessTokenKey);
    await _secure.delete(key: _refreshTokenKey);
    await _secure.delete(key: _userModeKey);
    await _secure.delete(key: _lastLoginAtKey);
    await _secure.delete(key: _tokenExpiresAtKey);
  }
}

class TokenStorageConfig {
  static String api(String path) => ApiConfig.api(path);
}

