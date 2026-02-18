import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'token_storage.dart';

class SessionRestoreResult {
  const SessionRestoreResult({
    required this.authenticated,
    required this.usedRefresh,
    required this.routedToLogin,
    this.user,
  });

  final bool authenticated;
  final bool usedRefresh;
  final bool routedToLogin;
  final Map<String, dynamic>? user;
}

class ApiService {
  static final ApiClient _client = ApiClient.instance;

  static String? _token;
  static String? get token => _token;

  static int? lastMeStatusCode;
  static DateTime? lastMeAt;
  static String? lastAuthError;
  static DateTime? _lastSessionValidationAt;

  static void setToken(String? token) {
    _token = token;
    if (token == null || token.isEmpty) {
      _client.clearAuthToken();
    } else {
      _client.setAuthToken(token);
    }
  }

  static Map<String, dynamic>? _unwrapUser(dynamic data) {
    if (data is Map<String, dynamic>) {
      final nested = data['user'];
      if (nested is Map<String, dynamic>) return nested;
      if (data['id'] != null) return data;
      return null;
    }
    if (data is Map) {
      return _unwrapUser(data.map((k, v) => MapEntry('$k', v)));
    }
    return null;
  }

  static Future<void> persistAuthPayload(Map<String, dynamic> data) async {
    final t = (data['token'] ?? data['access_token'] ?? '').toString().trim();
    if (t.isEmpty) return;
    final refreshToken = (data['refresh_token'] ?? '').toString().trim();
    final expiresAt = (data['expires_at'] ?? '').toString().trim();
    final user = _unwrapUser(data);
    final role = (user?['role'] ?? '').toString().trim();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    setToken(t);
    await TokenStorage().saveSession(
      accessToken: t,
      refreshToken: refreshToken.isEmpty ? null : refreshToken,
      userMode: role.isEmpty ? null : role,
      lastLoginAt: nowIso,
      tokenExpiresAt: expiresAt.isEmpty ? null : expiresAt,
    );
    _lastSessionValidationAt = DateTime.now();
  }

  static Future<void> resetAuthSession() async {
    final refreshToken =
        ((await TokenStorage().readRefreshToken()) ?? '').trim();
    final hasAccess = (_token ?? '').trim().isNotEmpty;
    if (hasAccess || refreshToken.isNotEmpty) {
      try {
        await _client.dio.post(
          ApiConfig.api('/auth/logout'),
          data: {
            if (refreshToken.isNotEmpty) 'refresh_token': refreshToken,
          },
        );
      } catch (_) {
        // best effort server-side revocation; local clear still proceeds
      }
    }
    await TokenStorage().clear();
    setToken(null);
    _client.resetSession();
    await syncSentryUser(null);
    lastMeStatusCode = null;
    lastMeAt = null;
    lastAuthError = null;
    _lastSessionValidationAt = null;
  }

  static Future<void> syncSentryUser(Map<String, dynamic>? user) async {
    final id = (user?['id'] ?? '').toString().trim();
    final email = (user?['email'] ?? '').toString().trim();
    if (id.isEmpty && email.isEmpty) {
      await Sentry.configureScope((scope) {
        scope.setUser(null);
      });
      return;
    }
    await Sentry.configureScope((scope) {
      scope.setUser(
        SentryUser(
          id: id.isEmpty ? null : id,
          email: email.isEmpty ? null : email,
        ),
      );
    });
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

  static bool isPhoneNotVerified(dynamic data) {
    if (data is Map) {
      final err = (data['error'] ?? '').toString().toLowerCase();
      if (err == 'phone_not_verified') return true;
      final msg = (data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('verify your phone') ||
          msg.contains('phone verification required') ||
          msg.contains('phone must be verified')) {
        return true;
      }
    }
    if (data is String) {
      final msg = data.toLowerCase();
      if (msg.contains('verify your phone') ||
          msg.contains('phone verification required') ||
          msg.contains('phone must be verified')) {
        return true;
      }
    }
    return false;
  }

  static bool isChatNotAllowed(dynamic data) {
    if (data is Map) {
      final err = (data['error'] ?? '').toString().toLowerCase();
      if (err == 'chat_not_allowed') return true;
      final msg = (data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('chat with admin') ||
          msg.contains('only chat with admin')) {
        return true;
      }
    }
    if (data is String) {
      final msg = data.toLowerCase();
      if (msg.contains('chat with admin') ||
          msg.contains('only chat with admin')) {
        return true;
      }
    }
    return false;
  }

  static bool isSellerCannotBuyOwnListing(dynamic data) {
    if (data is Map) {
      final err = (data['error'] ?? '').toString().toLowerCase();
      if (err == 'seller_cannot_buy_own_listing') return true;
      final msg = (data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('own listing')) return true;
    }
    if (data is String) {
      final msg = data.toLowerCase();
      if (msg.contains('own listing')) return true;
    }
    return false;
  }

  static bool isTierOrKycRestriction(dynamic data) {
    if (data is Map) {
      final err = (data['error'] ?? '').toString().toLowerCase();
      if (err.contains('kyc') ||
          err.contains('tier') ||
          err.contains('not_eligible')) return true;
      final msg = (data['message'] ?? '').toString().toLowerCase();
      if (msg.contains('kyc') ||
          msg.contains('tier') ||
          msg.contains('not eligible')) return true;
    }
    if (data is String) {
      final msg = data.toLowerCase();
      if (msg.contains('kyc') ||
          msg.contains('tier') ||
          msg.contains('not eligible')) return true;
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

    await persistAuthPayload(data);
    await syncSentryUser(_asMap(data['user']));

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

    await persistAuthPayload(data);
    await syncSentryUser(_asMap(data['user']));

    return data;
  }

  static Future<bool> refreshSession({String? refreshToken}) async {
    final rt =
        (refreshToken ?? await TokenStorage().readRefreshToken() ?? '').trim();
    if (rt.isEmpty) return false;
    final url = ApiConfig.api('/auth/refresh');
    try {
      final res = await _client.dio.post(url, data: {'refresh_token': rt});
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        return false;
      }
      final data = _asMap(res.data);
      await persistAuthPayload(data);
      final meRes = await getProfileResponse();
      if ((meRes.statusCode ?? 0) >= 200 && (meRes.statusCode ?? 0) < 300) {
        await syncSentryUser(_unwrapUser(meRes.data));
      }
      return true;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<SessionRestoreResult> restoreSession({
    Future<String?> Function()? readAccessToken,
    Future<String?> Function()? readRefreshToken,
    Future<Response<dynamic>> Function()? meCall,
    Future<bool> Function(String refreshToken)? refreshCall,
    Future<void> Function()? resetAuthSessionCall,
  }) async {
    final accessToken =
        ((await (readAccessToken?.call() ?? TokenStorage().readToken())) ?? '')
            .trim();
    if (accessToken.isEmpty) {
      setToken(null);
      return const SessionRestoreResult(
        authenticated: false,
        usedRefresh: false,
        routedToLogin: true,
      );
    }

    setToken(accessToken);
    try {
      final meRes = await (meCall?.call() ?? getProfileResponse());
      final status = meRes.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final user = _unwrapUser(meRes.data);
        await syncSentryUser(user);
        _lastSessionValidationAt = DateTime.now();
        return SessionRestoreResult(
          authenticated: user != null,
          usedRefresh: false,
          routedToLogin: user == null,
          user: user,
        );
      }
      if (status == 401) {
        final rt = ((await (readRefreshToken?.call() ??
                    TokenStorage().readRefreshToken())) ??
                '')
            .trim();
        final refreshed = rt.isNotEmpty
            ? await (refreshCall?.call(rt) ?? refreshSession(refreshToken: rt))
            : false;
        if (refreshed) {
          final retry = await (meCall?.call() ?? getProfileResponse());
          final retryStatus = retry.statusCode ?? 0;
          if (retryStatus >= 200 && retryStatus < 300) {
            final user = _unwrapUser(retry.data);
            await syncSentryUser(user);
            _lastSessionValidationAt = DateTime.now();
            return SessionRestoreResult(
              authenticated: user != null,
              usedRefresh: true,
              routedToLogin: user == null,
              user: user,
            );
          }
        }
      }
      await (resetAuthSessionCall?.call() ?? resetAuthSession());
      return const SessionRestoreResult(
        authenticated: false,
        usedRefresh: false,
        routedToLogin: true,
      );
    } catch (_) {
      await (resetAuthSessionCall?.call() ?? resetAuthSession());
      return const SessionRestoreResult(
        authenticated: false,
        usedRefresh: false,
        routedToLogin: true,
      );
    }
  }

  static Future<Map<String, dynamic>> requestPhoneOtp({
    required String phone,
  }) async {
    final url = ApiConfig.api('/auth/otp/request');
    final res = await _client.dio.post(url, data: {'phone': phone.trim()});
    return _asMap(res.data);
  }

  static Future<Map<String, dynamic>> verifyPhoneOtp({
    required String phone,
    required String code,
  }) async {
    final url = ApiConfig.api('/auth/otp/verify');
    final res = await _client.dio.post(
      url,
      data: {
        'phone': phone.trim(),
        'code': code.trim(),
      },
    );
    final data = _asMap(res.data);
    await persistAuthPayload(data);
    await syncSentryUser(_asMap(data['user']));
    return data;
  }

  static Future<void> revalidateSessionOnResume({
    Duration minimumInterval = const Duration(minutes: 10),
  }) async {
    final t = (_token ?? '').trim();
    if (t.isEmpty) return;
    final now = DateTime.now();
    if (_lastSessionValidationAt != null &&
        now.difference(_lastSessionValidationAt!) < minimumInterval) {
      return;
    }
    final result = await restoreSession();
    if (!result.authenticated) {
      lastAuthError = 'Session expired, please log in again.';
    }
    _lastSessionValidationAt = DateTime.now();
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
  // PASSWORD RESET
  // ---------------------------

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
      _recordMeStatus(e.response?.statusCode, e.response?.data,
          error: e.message);
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
