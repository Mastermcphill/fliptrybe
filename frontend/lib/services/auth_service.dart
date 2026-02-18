import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'api_service.dart';

class AuthService {
  final ApiClient _client = ApiClient.instance;
  bool _looksLikeUser(Map<String, dynamic> u) {
    final id = u['id'];
    final email = u['email'];
    final name = u['name'];

    final hasId = id is int || (id is String && id.trim().isNotEmpty);
    final hasEmail = email is String && email.trim().isNotEmpty;
    final hasName = name is String && name.trim().isNotEmpty;

    return hasId && (hasEmail || hasName);
  }

  Map<String, dynamic>? _unwrapUser(dynamic data) {
    if (data is Map<String, dynamic>) {
      // backend may return {"user": {...}}
      final maybeUser = data['user'];
      if (maybeUser is Map<String, dynamic> && _looksLikeUser(maybeUser)) {
        return maybeUser;
      }
      // or it may return the user object directly
      if (_looksLikeUser(data)) {
        return data;
      }
    }
    if (data is Map) {
      final cast = data.map((k, v) => MapEntry('$k', v));
      return _unwrapUser(cast);
    }
    return null;
  }

  /// Never let auth checks crash the app.
  /// Returns a valid user map only (never returns error maps).
  Future<Map<String, dynamic>?> me() async {
    try {
      final t = ApiService.token;
      if (t == null || t.isEmpty) return null;
      final raw = await ApiService.getProfile();
      return _unwrapUser(raw);
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> requestOtp(String phone) async {
    try {
      final res = await ApiService.requestPhoneOtp(phone: phone);
      return res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> verifyOtp(String phone, String code) async {
    try {
      final res = await ApiService.verifyPhoneOtp(phone: phone, code: code);
      final t = (res['token'] ?? res['access_token']);
      if (t is String && t.isNotEmpty) return t;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool> setRole(String role) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/auth/set-role'),
        data: {'role': role},
      );
      return res.data is Map && res.data['ok'] == true;
    } catch (_) {
      return false;
    }
  }
}
