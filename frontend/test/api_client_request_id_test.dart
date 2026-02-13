import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_client.dart';
import 'package:fliptrybe/services/api_config.dart';

class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
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

  test('ApiClient sends X-Request-ID header on requests', () async {
    final client = ApiClient.instance;
    final adapter = _CaptureAdapter();
    client.dio.httpClientAdapter = adapter;

    await client.dio.get(ApiConfig.api('/health'));

    final headers = adapter.lastRequest?.headers ?? const <String, dynamic>{};
    final requestId = (headers['X-Request-ID'] ?? '').toString();
    expect(requestId.isNotEmpty, isTrue);
    expect(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
            .hasMatch(requestId),
        isTrue);
  });
}
