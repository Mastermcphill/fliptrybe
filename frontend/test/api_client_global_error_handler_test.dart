import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_client.dart';
import 'package:fliptrybe/services/api_config.dart';

class _GlobalHandlerAdapter implements HttpClientAdapter {
  _GlobalHandlerAdapter({required this.statusCode});

  final int statusCode;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      '{"ok":false}',
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('global unauthorized handler fires for authenticated 401', () async {
    final client = ApiClient.instance;
    client.setAuthToken('token-1');
    client.dio.httpClientAdapter = _GlobalHandlerAdapter(statusCode: 401);

    var unauthorizedHits = 0;
    final errors = <String>[];
    client.configureGlobalHandlers(
      onUnauthorized: () async {
        unauthorizedHits += 1;
      },
      onErrorMessage: errors.add,
    );

    await client.dio.get(ApiConfig.api('/api/me/preferences'));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(unauthorizedHits, 1);
    expect(
      errors.any((m) => m.toLowerCase().contains('session expired')),
      isTrue,
    );
  });

  test('blocked unauthenticated /me call does not trigger forced reauth',
      () async {
    final client = ApiClient.instance;
    client.resetSession();
    client.dio.httpClientAdapter = _GlobalHandlerAdapter(statusCode: 200);

    var unauthorizedHits = 0;
    client.configureGlobalHandlers(
      onUnauthorized: () async {
        unauthorizedHits += 1;
      },
      onErrorMessage: (_) {},
    );

    await client.dio.get(ApiConfig.api('/api/me/preferences'));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(unauthorizedHits, 0);
  });
}
