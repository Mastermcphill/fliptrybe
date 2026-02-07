import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_config.dart';

class ApiClient {
  ApiClient._internal();
  static final ApiClient instance = ApiClient._internal();
  String? _authToken;

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
          final token = _authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          } else {
            options.headers.remove('Authorization');
          }
          options.headers['X-Fliptrybe-Client'] = ApiConfig.clientFingerprint;
          // ignore: avoid_print
          print('*** Request ***');
          // ignore: avoid_print
          print('uri: ${options.uri}');
          // ignore: avoid_print
          print('method: ${options.method}');
          // ignore: avoid_print
          print('responseType: ${options.responseType}');
          // ignore: avoid_print
          print('followRedirects: ${options.followRedirects}');
          // ignore: avoid_print
          print('persistentConnection: ${options.persistentConnection}');
          // ignore: avoid_print
          print('connectTimeout: ${options.connectTimeout}');
          // ignore: avoid_print
          print('sendTimeout: ${options.sendTimeout}');
          // ignore: avoid_print
          print('receiveTimeout: ${options.receiveTimeout}');
          // ignore: avoid_print
          print('receiveDataWhenStatusError: ${options.receiveDataWhenStatusError}');
          // ignore: avoid_print
          print('extra: ${options.extra}');
          // ignore: avoid_print
          print('data: ${options.data}');
          // ignore: avoid_print
          print('');

          return handler.next(options);
        },
        onResponse: (response, handler) {
          // ignore: avoid_print
          print('*** Response ***');
          // ignore: avoid_print
          print('uri: ${response.realUri}');
          // ignore: avoid_print
          print('statusCode: ${response.statusCode}');
          // ignore: avoid_print
          print('Response Text:');
          // ignore: avoid_print
          print(response.data);
          // ignore: avoid_print
          print('');

          return handler.next(response);
        },
        onError: (e, handler) {
          // Mostly for network errors/timeouts now (5xx won't throw either).
          // ignore: avoid_print
          print('*** DioException ***:');
          // ignore: avoid_print
          print('uri: ${e.requestOptions.uri}');
          // ignore: avoid_print
          print(e);
          // ignore: avoid_print
          if (e.response != null) {
            print('*** Error Response ***');
            print('statusCode: ${e.response?.statusCode}');
            print(e.response?.data);
          }
          // ignore: avoid_print
          print('');

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
