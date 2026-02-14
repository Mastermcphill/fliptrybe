import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/screens/admin_support_thread_screen.dart';
import 'package:fliptrybe/services/api_client.dart';
import 'package:fliptrybe/services/support_service.dart';

class _FakeSupportService extends SupportService {
  _FakeSupportService() : super(client: ApiClient.instance);

  int replyCalls = 0;
  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[
    {
      'id': 1,
      'thread_id': 99,
      'user_id': 99,
      'sender_role': 'user',
      'sender_user_id': 99,
      'sender_id': 99,
      'body': 'Initial user message',
      'created_at': '2026-02-14T00:00:00Z',
    }
  ];

  @override
  Future<List<Map<String, dynamic>>> adminThreadMessages(int threadId) async {
    return List<Map<String, dynamic>>.from(_messages);
  }

  @override
  Future<Map<String, dynamic>> adminReply({
    required int threadId,
    required String body,
  }) async {
    replyCalls += 1;
    final created = <String, dynamic>{
      'id': 2,
      'thread_id': threadId,
      'user_id': threadId,
      'sender_role': 'admin',
      'sender_user_id': 1,
      'sender_id': 1,
      'body': body,
      'created_at': '2026-02-14T00:00:01Z',
    };
    _messages.add(created);
    return {
      'ok': true,
      'message': created,
    };
  }
}

void main() {
  testWidgets('admin support reply sends once and renders message', (
    tester,
  ) async {
    final fake = _FakeSupportService();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminSupportThreadScreen(
          userId: 99,
          userEmail: 'user@fliptrybe.test',
          supportService: fake,
          forceAdmin: true,
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Initial user message'), findsOneWidget);
    expect(fake.replyCalls, 0);

    await tester.enterText(
      find.byType(TextField).first,
      'Support response from admin',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(fake.replyCalls, 1);
    expect(find.text('Support response from admin'), findsOneWidget);
  });
}
