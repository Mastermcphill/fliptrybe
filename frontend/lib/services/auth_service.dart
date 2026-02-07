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

  /// Demo OTP: returns true so UI can move to OTP step.
  Future<bool> requestOtp(String phone) async {
    return true;
  }

  /// Demo OTP verify: returns a REAL backend token by registering/logging in.
  /// ApiService.register/login will automatically set the token into Dio headers.
  Future<String?> verifyOtp(String phone, String code) async {
    final safePhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final demoEmail = 'phone_${safePhone.isEmpty ? "user" : safePhone}@fliptrybe.dev';
    const demoPassword = '12345678';

    try {
      final reg = await ApiService.register(
        name: 'FlipTrybe User',
        email: demoEmail,
        password: demoPassword,
        phone: phone,
      );

      final t = reg['token'];
      if (t is String && t.isNotEmpty) return t;
    } catch (_) {
      // fall through to login
    }

    try {
      final login = await ApiService.login(
        email: demoEmail,
        password: demoPassword,
      );

      final t = login['token'];
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
