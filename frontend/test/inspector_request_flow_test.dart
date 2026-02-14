import 'package:fliptrybe/screens/inspector_request_received_screen.dart';
import 'package:fliptrybe/services/api_client.dart';
import 'package:fliptrybe/services/api_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inspector request success screen shows login CTA',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InspectorRequestReceivedScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Inspector request received'), findsOneWidget);
    expect(find.text('Log in to track status'), findsOneWidget);
  });

  test('ApiClient blocks protected role request endpoint without token',
      () async {
    ApiClient.instance.clearAuthToken();
    final response = await ApiClient.instance.getJson(
      ApiConfig.api('/role-requests/me'),
    );

    expect(response, isA<Map>());
    expect(response['code'], 'NOT_AUTHENTICATED');
    expect(response['requires_auth'], true);
  });
}
