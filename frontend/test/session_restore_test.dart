import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_service.dart';

Response<dynamic> _response(int code, dynamic data) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/auth/me'),
    statusCode: code,
    data: data,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restoreSession authenticates when access token is valid', () async {
    final result = await ApiService.restoreSession(
      readAccessToken: () async => 'access-token',
      meCall: () async => _response(200, {
        'id': 1,
        'email': 'buyer@fliptrybe.test',
        'role': 'buyer',
      }),
      resetAuthSessionCall: () async {},
    );

    expect(result.authenticated, isTrue);
    expect(result.usedRefresh, isFalse);
    expect(result.routedToLogin, isFalse);
    expect(result.user?['email'], 'buyer@fliptrybe.test');
  });

  test(
      'restoreSession refreshes and authenticates when access token is expired but refresh exists',
      () async {
    var meCalls = 0;
    var refreshCalls = 0;
    final result = await ApiService.restoreSession(
      readAccessToken: () async => 'expired-access-token',
      readRefreshToken: () async => 'refresh-token',
      meCall: () async {
        meCalls += 1;
        if (meCalls == 1) {
          return _response(401, {'message': 'Invalid or expired token'});
        }
        return _response(200, {
          'id': 9,
          'email': 'merchant@fliptrybe.test',
          'role': 'merchant',
        });
      },
      refreshCall: (refreshToken) async {
        refreshCalls += 1;
        return refreshToken == 'refresh-token';
      },
      resetAuthSessionCall: () async {},
    );

    expect(refreshCalls, 1);
    expect(meCalls, 2);
    expect(result.authenticated, isTrue);
    expect(result.usedRefresh, isTrue);
    expect(result.routedToLogin, isFalse);
    expect(result.user?['role'], 'merchant');
  });

  test('restoreSession routes to login when access and refresh are invalid',
      () async {
    var resetCalled = false;

    final result = await ApiService.restoreSession(
      readAccessToken: () async => 'expired-access-token',
      readRefreshToken: () async => 'expired-refresh-token',
      meCall: () async => _response(401, {'message': 'Invalid or expired token'}),
      refreshCall: (_) async => false,
      resetAuthSessionCall: () async {
        resetCalled = true;
      },
    );

    expect(resetCalled, isTrue);
    expect(result.authenticated, isFalse);
    expect(result.routedToLogin, isTrue);
  });
}
