import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fliptrybe/services/notification_service.dart';

void main() {
  test('markAsRead succeeds for local non-numeric ids without backend call', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'notifications_cache_v1': jsonEncode([
        {
          'id': 'local-demo-1',
          'title': 'Draft',
          'body': 'Local notification',
          'created_at': now,
          'is_read': false,
          'channel': 'in_app',
        }
      ]),
      'notifications_read_ids_v1': <String>[],
    });

    final rows = await NotificationService.instance.loadInbox(refresh: false);
    expect(rows, isNotEmpty);
    expect(rows.first.isRead, isFalse);

    final ok = await NotificationService.instance.markAsRead('local-demo-1');
    expect(ok, isTrue);
    expect(NotificationService.instance.unreadCount.value, 0);
  });
}
