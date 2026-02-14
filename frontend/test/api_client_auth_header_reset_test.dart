import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_client.dart';
import 'package:fliptrybe/services/api_config.dart';

class _AuthCaptureAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ApiClient does not keep stale auth headers after resetSession',
      () async {
    final client = ApiClient.instance;
    final adapter = _AuthCaptureAdapter();
    client.dio.httpClientAdapter = adapter;

    for (var cycle = 1; cycle <= 3; cycle++) {
      final token = 'token-$cycle';
      client.setAuthToken(token);

      await client.dio.get(ApiConfig.api('/api/me/preferences'));
      final authHeader =
          (adapter.requests.last.headers['Authorization'] ?? '').toString();
      expect(authHeader, 'Bearer $token');

      client.resetSession();
      expect(client.dio.options.headers.containsKey('Authorization'), isFalse);

      await client.dio.get(ApiConfig.api('/api/public/listings/recommended'));
      final postLogoutHeaders = adapter.requests.last.headers;
      expect(postLogoutHeaders.containsKey('Authorization'), isFalse);
    }
  });
}
