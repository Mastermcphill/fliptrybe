import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient._internal();
  static final ApiClient instance = ApiClient._internal();
  String? _authToken;
  final Set<CancelToken> _activeCancelTokens = <CancelToken>{};
  final Random _rand = Random();

  String _newRequestId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nonce = _rand.nextInt(1 << 32).toRadixString(16);
    return "ft-$now-$nonce";
  }

  late final Dio dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 10),

      // ✅ Don't throw on 401/404; only treat 5xx as errors.
      validateStatus: (status) => status != null && status < 500,

      responseType: ResponseType.json,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Fliptrybe-Client': ApiConfig.clientFingerprint,
      },
    ),
  )..interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final cancelToken = options.cancelToken ?? CancelToken();
          options.cancelToken = cancelToken;
          _activeCancelTokens.add(cancelToken);
          final token = _authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          options.headers['X-Request-Id'] = _newRequestId();
          options.headers['X-Fliptrybe-Client'] = ApiConfig.clientFingerprint;
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.request',
            type: 'http',
            level: SentryLevel.info,
            data: {
              'method': options.method,
              'url': options.uri.toString(),
            },
          ));
          // ignore: avoid_print
          if (kDebugMode) {
            debugPrint('[ApiClient] ${options.method} ${options.uri}');
          }

          return handler.next(options);
        },
        onResponse: (response, handler) {
          final token = response.requestOptions.cancelToken;
          if (token != null) _activeCancelTokens.remove(token);
          // ignore: avoid_print
          if (kDebugMode) {
            debugPrint('[ApiClient] ${response.requestOptions.method} ${response.realUri} -> ${response.statusCode}');
          }
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.response',
            type: 'http',
            level: SentryLevel.info,
            data: {
              'method': response.requestOptions.method,
              'url': response.realUri.toString(),
              'status': response.statusCode,
            },
          ));

          return handler.next(response);
        },
        onError: (e, handler) {
          final token = e.requestOptions.cancelToken;
          if (token != null) _activeCancelTokens.remove(token);
          // Mostly for network errors/timeouts now (5xx won't throw either).
          // ignore: avoid_print
          if (kDebugMode) {
            debugPrint('[ApiClient] ERROR ${e.requestOptions.method} ${e.requestOptions.uri} -> ${e.response?.statusCode} ${e.message}');
          }
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.error',
            type: 'http',
            level: SentryLevel.warning,
            data: {
              'method': e.requestOptions.method,
              'url': e.requestOptions.uri.toString(),
              'status': e.response?.statusCode,
            },
          ));
          Sentry.captureException(e);

          return handler.next(e);
        },
      ),
    );

  void setAuthToken(String token) {
    final t = token.trim();
    if (t.isEmpty) {
      clearAuthToken();
      return;
    }
    _authToken = t;
    dio.options.headers['Authorization'] = 'Bearer $t';
  }

  void clearAuthToken() {
    _authToken = null;
    dio.options.headers.remove('Authorization');
  }

  void cancelAllRequests([String reason = 'session_reset']) {
    final copy = _activeCancelTokens.toList(growable: false);
    for (final token in copy) {
      if (!token.isCancelled) token.cancel(reason);
    }
    _activeCancelTokens.clear();
  }

  void resetSession() {
    cancelAllRequests('logout');
    clearAuthToken();
  }

  dynamic jsonDecodeSafe(String s) {
    try {
      return json.decode(s);
    } catch (_) {
      return null;
    }
  }

  dynamic _normalizeData(dynamic data) {
    if (data == null) return <String, dynamic>{};
    if (data is String) {
      final decoded = jsonDecodeSafe(data);
      return decoded ?? <String, dynamic>{};
    }
    return data;
  }

  Future<dynamic> getJson(String url) async {
    try {
      final res = await dio.get(url);
      return _normalizeData(res.data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<dynamic> postJson(String url, Map<String, dynamic> body) async {
    try {
      final res = await dio.post(url, data: body);
      return _normalizeData(res.data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<dynamic> postMultipart(
    String url, {
    required Map<String, String> fields,
    required String fileField,
    required String filePath,
  }) async {
    final normalized = filePath.replaceAll('\\', '/');
    final filename = normalized.split('/').last;
    final form = FormData.fromMap({
      ...fields,
      fileField: await MultipartFile.fromFile(filePath, filename: filename),
    });
    try {
      final res = await dio.post(url, data: form);
      return _normalizeData(res.data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
