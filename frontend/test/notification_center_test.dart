import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fliptrybe/screens/notifications_inbox_screen.dart';
import 'package:fliptrybe/services/notification_service.dart';

void main() {
  testWidgets('Notification inbox marks unread item as read', (tester) async {
    final now = DateTime.now().toUtc().toIso8601String();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notifications_cache_v1': jsonEncode([
        {
          'id': 'n1',
          'title': 'Payment update',
          'body': 'Your payment is processing.',
          'created_at': now,
          'is_read': false,
          'channel': 'in_app',
        }
      ]),
      'notifications_read_ids_v1': <String>[],
    });

    await NotificationService.instance.loadInbox(refresh: false);

    await tester.pumpWidget(
      const MaterialApp(home: NotificationsInboxScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.text('Payment update'));
    await tester.pumpAndSettle();

    expect(find.text('NEW'), findsNothing);
  });
}
