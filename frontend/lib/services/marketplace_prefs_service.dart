import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_search_record.dart';

class MarketplacePrefsService {
  static const _favoritesKey = 'marketplace_favorites';
  static const _savedSearchesKey = 'marketplace_saved_searches';
  static const _lastCategoryKey = 'marketplace_last_category_context_v1';

  Future<Set<int>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_favoritesKey) ?? const <String>[];
    return raw.map((e) => int.tryParse(e) ?? -1).where((e) => e > 0).toSet();
  }

  Future<void> saveFavorites(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      ids.map((e) => e.toString()).toList(growable: false),
    );
  }

  Future<List<SavedSearchRecord>> loadSavedSearchRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedSearchesKey) ?? const <String>[];
    return raw
        .map((item) {
          try {
            final decoded = jsonDecode(item);
            if (decoded is Map) {
              return SavedSearchRecord.fromMap(
                Map<String, dynamic>.from(decoded),
              );
            }
          } catch (_) {}
          return null;
        })
        .whereType<SavedSearchRecord>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> loadSavedSearches() async {
    final rows = await loadSavedSearchRecords();
    return rows.map((record) => record.toMap()).toList(growable: false);
  }

  Future<void> saveSavedSearchesRecords(List<SavedSearchRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = records
        .map((record) => jsonEncode(record.toMap()))
        .toList(growable: false);
    await prefs.setStringList(_savedSearchesKey, raw);
  }

  Future<void> saveSavedSearches(List<Map<String, dynamic>> searches) async {
    final records = searches
        .map((map) => SavedSearchRecord.fromMap(map))
        .where((record) => record.key.isNotEmpty)
        .toList(growable: false);
    await saveSavedSearchesRecords(records);
  }

  Future<void> upsertSearch(Map<String, dynamic> search) async {
    final existing = await loadSavedSearchRecords();
    final key = (search['key'] ?? '').toString().trim();
    if (key.isEmpty) return;

    final now = DateTime.now().toUtc();
    final incoming = SavedSearchRecord.fromMap({
      ...search,
      'key': key,
      'createdAt': search['createdAt'] ?? now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    final idx = existing.indexWhere((item) => item.key == key);
    if (idx >= 0) {
      final current = existing[idx];
      existing[idx] = SavedSearchRecord(
        key: key,
        state: incoming.state,
        createdAt: current.createdAt,
        updatedAt: now,
      );
    } else {
      existing.insert(0, incoming);
    }

    if (existing.length > 30) {
      existing.removeRange(30, existing.length);
    }
    await saveSavedSearchesRecords(existing);
  }

  Future<void> deleteSearch(String key) async {
    final existing = await loadSavedSearchRecords();
    existing.removeWhere((record) => record.key == key);
    await saveSavedSearchesRecords(existing);
  }

  Future<void> saveLastCategoryContext({
    required String category,
    int? categoryId,
    int? parentCategoryId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'category': category,
      'categoryId': categoryId,
      'parentCategoryId': parentCategoryId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    await prefs.setString(_lastCategoryKey, jsonEncode(payload));
  }

  Future<Map<String, dynamic>> loadLastCategoryContext() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastCategoryKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return const <String, dynamic>{};
  }
}
