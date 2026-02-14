import 'dart:async';
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
  final Random _rand = Random.secure();
  String? _lastFailedRequestId;
  final ValueNotifier<bool> networkOnline = ValueNotifier<bool>(true);
  Future<void> Function()? _onUnauthorized;
  void Function(String message)? _onGlobalErrorMessage;
  bool _forcingReauth = false;
  static const Map<String, dynamic> _notAuthenticatedResponse =
      <String, dynamic>{
    'ok': false,
    'code': 'NOT_AUTHENTICATED',
    'message': 'Not authenticated',
    'requires_auth': true,
  };

  String _newRequestId() {
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _rand.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final parts = bytes.map(hex).toList(growable: false);
    return [
      parts.sublist(0, 4).join(),
      parts.sublist(4, 6).join(),
      parts.sublist(6, 8).join(),
      parts.sublist(8, 10).join(),
      parts.sublist(10, 16).join(),
    ].join('-');
  }

  String? get lastFailedRequestId => _lastFailedRequestId;

  void _setNetworkOnline(bool online) {
    if (networkOnline.value == online) return;
    networkOnline.value = online;
  }

  void configureGlobalHandlers({
    Future<void> Function()? onUnauthorized,
    void Function(String message)? onErrorMessage,
  }) {
    _onUnauthorized = onUnauthorized;
    _onGlobalErrorMessage = onErrorMessage;
  }

  void clearLastFailedRequestId() {
    _lastFailedRequestId = null;
  }

  String _requestIdFromHeaders(dynamic headers) {
    if (headers == null) return '';
    try {
      final value =
          headers.value('X-Request-ID') ?? headers.value('X-Request-Id');
      return (value ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  String _requestIdForFailure(
      Response<dynamic>? response, RequestOptions requestOptions) {
    final fromResponse = _requestIdFromHeaders(response?.headers);
    if (fromResponse.isNotEmpty) return fromResponse;
    final reqHeader = requestOptions.headers['X-Request-ID'] ??
        requestOptions.headers['X-Request-Id'];
    return (reqHeader ?? '').toString().trim();
  }

  bool _hasAuthToken() {
    final token = _authToken?.trim() ?? '';
    return token.isNotEmpty;
  }

  void _emitGlobalErrorMessage(String message, {String? requestId}) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;
    final rid = (requestId ?? '').trim();
    if (_onGlobalErrorMessage == null) return;
    if (rid.isNotEmpty) {
      _onGlobalErrorMessage!("$trimmed (Support code: $rid)");
      return;
    }
    _onGlobalErrorMessage!(trimmed);
  }

  void _scheduleUnauthorized(RequestOptions requestOptions) {
    final authHeader =
        (requestOptions.headers['Authorization'] ?? '').toString().trim();
    if (authHeader.isEmpty) return;
    final handler = _onUnauthorized;
    if (handler == null || _forcingReauth) return;
    _forcingReauth = true;
    unawaited(
      handler().catchError((_) {}).whenComplete(() {
        _forcingReauth = false;
      }),
    );
  }

  bool _requiresAuth(Uri uri) {
    final segments = uri.pathSegments
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return false;

    final containsMe = segments.contains('me');
    final isAdmin =
        segments.length >= 2 && segments[0] == 'api' && segments[1] == 'admin';
    final isRoleRequests = segments.length >= 2 &&
        segments[0] == 'api' &&
        segments[1] == 'role-requests';
    return containsMe || isAdmin || isRoleRequests;
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
          final requestId = _newRequestId();
          options.headers['X-Request-ID'] = requestId;
          options.headers['X-Fliptrybe-Client'] = ApiConfig.clientFingerprint;
          // Always rebuild Authorization from in-memory token per request.
          // This prevents any stale header reuse across logout/login cycles.
          options.headers.remove('Authorization');
          if (_requiresAuth(options.uri) && !_hasAuthToken()) {
            if (kDebugMode) {
              debugPrint(
                  '[ApiClient] BLOCKED unauthenticated ${options.method} ${options.uri}');
            }
            _lastFailedRequestId = requestId;
            return handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 401,
                statusMessage: 'Not authenticated',
                data: <String, dynamic>{
                  ..._notAuthenticatedResponse,
                  'path': options.uri.path,
                  'trace_id': requestId,
                },
              ),
            );
          }
          final cancelToken = options.cancelToken ?? CancelToken();
          options.cancelToken = cancelToken;
          _activeCancelTokens.add(cancelToken);
          final token = (_authToken ?? '').trim();
          if (token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.request',
            type: 'http',
            level: SentryLevel.info,
            data: {
              'method': options.method,
              'url': options.uri.toString(),
              'request_id': requestId,
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
          _setNetworkOnline(true);
          // ignore: avoid_print
          if (kDebugMode) {
            debugPrint(
                '[ApiClient] ${response.requestOptions.method} ${response.realUri} -> ${response.statusCode}');
          }
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.response',
            type: 'http',
            level: SentryLevel.info,
            data: {
              'method': response.requestOptions.method,
              'url': response.realUri.toString(),
              'status': response.statusCode,
              'request_id': _requestIdFromHeaders(response.headers),
            },
          ));
          if ((response.statusCode ?? 0) >= 400) {
            _lastFailedRequestId =
                _requestIdForFailure(response, response.requestOptions);
          }
          if (response.statusCode == 401) {
            _scheduleUnauthorized(response.requestOptions);
            _emitGlobalErrorMessage(
              'Session expired, please log in again',
              requestId:
                  _requestIdForFailure(response, response.requestOptions),
            );
          } else if ((response.statusCode ?? 0) >= 500) {
            _emitGlobalErrorMessage(
              'Server hiccup, try again',
              requestId:
                  _requestIdForFailure(response, response.requestOptions),
            );
          }

          return handler.next(response);
        },
        onError: (e, handler) {
          final token = e.requestOptions.cancelToken;
          if (token != null) _activeCancelTokens.remove(token);
          // Mostly for network errors/timeouts now (5xx won't throw either).
          // ignore: avoid_print
          if (kDebugMode) {
            debugPrint(
                '[ApiClient] ERROR ${e.requestOptions.method} ${e.requestOptions.uri} -> ${e.response?.statusCode} ${e.message}');
          }
          final rid = _requestIdForFailure(e.response, e.requestOptions);
          _lastFailedRequestId = rid.isNotEmpty ? rid : _lastFailedRequestId;
          if (e.response?.statusCode == 401) {
            _scheduleUnauthorized(e.requestOptions);
            _emitGlobalErrorMessage(
              'Session expired, please log in again',
              requestId: rid,
            );
          } else if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError) {
            _setNetworkOnline(false);
            _emitGlobalErrorMessage(
              'Network timeout, try again',
              requestId: rid,
            );
          } else if ((e.response?.statusCode ?? 0) >= 500) {
            _emitGlobalErrorMessage(
              'Server hiccup, try again',
              requestId: rid,
            );
          }
          Sentry.addBreadcrumb(Breadcrumb(
            category: 'http.error',
            type: 'http',
            level: SentryLevel.warning,
            data: {
              'method': e.requestOptions.method,
              'url': e.requestOptions.uri.toString(),
              'status': e.response?.statusCode,
              'request_id': rid,
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
