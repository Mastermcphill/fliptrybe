import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MarketplacePrefsService {
  static const _favoritesKey = 'marketplace_favorites';
  static const _savedSearchesKey = 'marketplace_saved_searches';

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

  Future<List<Map<String, dynamic>>> loadSavedSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_savedSearchesKey) ?? const <String>[];
    return raw
        .map((item) {
          try {
            final decoded = jsonDecode(item);
            if (decoded is Map) return Map<String, dynamic>.from(decoded);
          } catch (_) {}
          return <String, dynamic>{};
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  Future<void> saveSavedSearches(List<Map<String, dynamic>> searches) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = searches.map((m) => jsonEncode(m)).toList(growable: false);
    await prefs.setStringList(_savedSearchesKey, raw);
  }

  Future<void> upsertSearch(Map<String, dynamic> search) async {
    final existing = await loadSavedSearches();
    final key = (search['key'] ?? '').toString();
    final now = DateTime.now().toIso8601String();
    final normalized = {
      ...search,
      'createdAt': search['createdAt'] ?? now,
      'updatedAt': now,
    };

    final idx = existing.indexWhere((m) => (m['key'] ?? '').toString() == key);
    if (idx >= 0) {
      existing[idx] = normalized;
    } else {
      existing.insert(0, normalized);
    }

    if (existing.length > 30) {
      existing.removeRange(30, existing.length);
    }
    await saveSavedSearches(existing);
  }

  Future<void> deleteSearch(String key) async {
    final existing = await loadSavedSearches();
    existing.removeWhere((m) => (m['key'] ?? '').toString() == key);
    await saveSavedSearches(existing);
  }
}
