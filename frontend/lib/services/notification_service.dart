import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/notification_item.dart';
import 'api_client.dart';
import 'api_config.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _cacheKey = 'notifications_cache_v1';
  static const String _readKey = 'notifications_read_ids_v1';

  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  Future<List<NotificationItem>> loadInbox({bool refresh = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeItems(prefs.getString(_cacheKey));
    final localRead = prefs.getStringList(_readKey)?.toSet() ?? <String>{};

    List<NotificationItem> merged = cached
        .map((item) =>
            item.copyWith(isRead: item.isRead || localRead.contains(item.id)))
        .toList(growable: true);

    if (refresh) {
      final remote = await _fetchRemote();
      if (remote.isNotEmpty) {
        final byId = <String, NotificationItem>{
          for (final item in merged) item.id: item,
        };
        for (final item in remote) {
          final prior = byId[item.id];
          if (prior == null || item.createdAt.isAfter(prior.createdAt)) {
            byId[item.id] = item;
          }
        }
        merged = byId.values
            .map((item) => item.copyWith(
                isRead: item.isRead || localRead.contains(item.id)))
            .toList(growable: false)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
    }

    await prefs.setString(
        _cacheKey, jsonEncode(merged.map((e) => e.toJson()).toList()));
    _syncUnread(merged);
    return merged;
  }

  // Compatibility adapter for older screens expecting dynamic maps.
  Future<List<dynamic>> inbox() async {
    final rows = await loadInbox(refresh: true);
    return rows.map((item) => item.toJson()).toList(growable: false);
  }

  Future<bool> markAsRead(String id) async {
    final safeId = id.trim();
    if (safeId.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final readSet = prefs.getStringList(_readKey)?.toSet() ?? <String>{};
    readSet.add(safeId);
    await prefs.setStringList(_readKey, readSet.toList(growable: false));

    final cached = _decodeItems(prefs.getString(_cacheKey))
        .map((item) => item.id == safeId ? item.copyWith(isRead: true) : item)
        .toList(growable: false);
    await prefs.setString(
        _cacheKey, jsonEncode(cached.map((e) => e.toJson()).toList()));
    _syncUnread(cached);

    try {
      final res = await ApiClient.instance.postJson(
        ApiConfig.api('/notifications/$safeId/read'),
        <String, dynamic>{},
      );
      return res is Map && res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> markAllRead() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _decodeItems(prefs.getString(_cacheKey));
    final ids = cached.map((e) => e.id).toSet();
    await prefs.setStringList(_readKey, ids.toList(growable: false));
    final marked = cached
        .map((item) => item.copyWith(isRead: true))
        .toList(growable: false);
    await prefs.setString(
        _cacheKey, jsonEncode(marked.map((e) => e.toJson()).toList()));
    _syncUnread(marked);
  }

  Future<bool> flushDemo() async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api('/notify/flush-demo'), {});
    return res is Map && res['ok'] == true;
  }

  Future<List<NotificationItem>> _fetchRemote() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/notify/inbox'));
    final List<dynamic> rows;
    if (data is List) {
      rows = data;
    } else if (data is Map && data['items'] is List) {
      rows = data['items'] as List<dynamic>;
    } else {
      rows = const <dynamic>[];
    }
    return rows
        .whereType<Map>()
        .map((raw) => NotificationItem.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
  }

  List<NotificationItem> _decodeItems(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <NotificationItem>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <NotificationItem>[];
      return decoded
          .whereType<Map>()
          .map((raw) =>
              NotificationItem.fromJson(Map<String, dynamic>.from(raw)))
          .toList(growable: false);
    } catch (_) {
      return const <NotificationItem>[];
    }
  }

  void _syncUnread(List<NotificationItem> items) {
    unreadCount.value = items.where((item) => !item.isRead).length;
  }
}
