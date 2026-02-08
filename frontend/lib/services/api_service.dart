import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'token_storage.dart';

class ApiService {
  static final ApiClient _client = ApiClient.instance;

  static String? _token;
  static String? get token => _token;

  static int? lastMeStatusCode;
  static DateTime? lastMeAt;
  static String? lastAuthError;

  static void setToken(String? token) {
    _token = token;
    if (token == null || token.isEmpty) {
      _client.clearAuthToken();
    } else {
      _client.setAuthToken(token);
    }
  }

  static void _recordMeStatus(int? statusCode, dynamic data, {String? error}) {
    lastMeStatusCode = statusCode;
    lastMeAt = DateTime.now();
    if (statusCode == 401 || error != null) {
      final msg = _extractAuthError(data) ?? error;
      if (msg != null && msg.isNotEmpty) {
        lastAuthError = msg;
      }
    } else if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      lastAuthError = null;
    }
  }

  static String? _extractAuthError(dynamic data) {
    if (data is Map) {
      if (data['message'] != null) return data['message'].toString();
      if (data['error'] != null) return data['error'].toString();
    }
    if (data is String && data.trim().isNotEmpty) return data;
    return null;
  }

  static bool isEmailNotVerified(dynamic data) {
    if (data is Map) {
      final err = (data['error'] ?? '').toString().toLowerCase();
      if (err == 'email_not_verified') return true;
      final msg = (data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('verify your email') || msg.contains('email verification required')) {
        return true;
      }
    }
    if (data is String) {
      final msg = data.toLowerCase();
      if (msg.contains('verify your email') || msg.contains('email verification required')) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------
  // AUTH
  // ---------------------------

  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    final url = ApiConfig.api('/auth/register');

    final payload = {
      'name': name,
      'email': email,
      'password': password,
    };
    if (phone != null && phone.trim().isNotEmpty) {
      payload['phone'] = phone.trim();
    }

    final res = await _client.dio.post(url, data: payload);

    final data = _asMap(res.data);

    final t = data['token'] ?? data['access_token'];
    if (t is String && t.isNotEmpty) {
      setToken(t);
      await TokenStorage().saveToken(t);
    }

    return data;
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final url = ApiConfig.api('/auth/login');

    final res = await _client.dio.post(url, data: {
      'email': email,
      'password': password,
    });

    final data = _asMap(res.data);

    final t = data['token'] ?? data['access_token'];
    if (t is String && t.isNotEmpty) {
      setToken(t);
      await TokenStorage().saveToken(t);
    }

    return data;
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final t = _token;
    if (t == null || t.isEmpty) {
      return {'message': 'Not logged in'};
    }
    final res = await getProfileResponse();
    return _asMap(res.data);
  }

  // ---------------------------
  // EMAIL VERIFICATION + PASSWORD RESET
  // ---------------------------

  static Future<Map<String, dynamic>> verifySend() async {
    final url = ApiConfig.api('/auth/verify-email/resend');
    final res = await _client.dio.post(url, data: {});
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> verifyConfirm({
    required String token,
  }) async {
    final url = ApiConfig.api('/auth/verify-email');
    final res = await _client.dio.get(url, queryParameters: {'token': token.trim()});
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> verifyStatus() async {
    final url = ApiConfig.api('/auth/verify-email/status');
    final res = await _client.dio.get(url);
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> passwordForgot(String email) async {
    final url = ApiConfig.api('/auth/password/forgot');
    final res = await _client.dio.post(url, data: {'email': email.trim()});
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> passwordReset({
    required String newPassword,
    required String token,
  }) async {
    final url = ApiConfig.api('/auth/password/reset');
    final payload = <String, dynamic>{'new_password': newPassword};
    payload['token'] = token.trim();
    final res = await _client.dio.post(url, data: payload);
    return _asMap(res.data);
  }

  static Future<Response<dynamic>> getProfileResponse() async {
    final url = ApiConfig.api('/auth/me');
    try {
      final res = await _client.dio.get(url);
      _recordMeStatus(res.statusCode, res.data);
      return res;
    } on DioException catch (e) {
      _recordMeStatus(e.response?.statusCode, e.response?.data, error: e.message);
      rethrow;
    }
  }

  // ---------------------------
  // RIDES
  // ---------------------------

  static Future<bool> requestRide(
    String pickup,
    String dropoff,
    String vehicle,
  ) async {
    final url = ApiConfig.api('/ride/request');

    try {
      final res = await _client.dio.post(url, data: {
        'pickup': pickup,
        'dropoff': dropoff,
        'vehicle': vehicle,
      });

      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return {'data': data};
  }
}
