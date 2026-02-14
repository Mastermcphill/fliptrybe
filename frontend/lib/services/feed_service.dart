import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';

class FeedService {
  static const _kCache = 'ft_feed_cache';

  final ApiClient _client = ApiClient.instance;

  /// GET /api/feed?state=...&city=...&locality=...
  Future<List<dynamic>> getFeed({
    String state = '',
    String city = '',
    String locality = '',
    String lga = '',
    double? lat,
    double? lng,
    double radiusKm = 10,
  }) async {
    final qp = <String>[];
    if (state.trim().isNotEmpty)
      qp.add('state=${Uri.encodeComponent(state.trim())}');
    if (city.trim().isNotEmpty)
      qp.add('city=${Uri.encodeComponent(city.trim())}');
    if (locality.trim().isNotEmpty)
      qp.add('locality=${Uri.encodeComponent(locality.trim())}');
    if (lga.trim().isNotEmpty) qp.add('lga=${Uri.encodeComponent(lga.trim())}');
    if (lat != null) qp.add('lat=${lat.toString()}');
    if (lng != null) qp.add('lng=${lng.toString()}');
    if (radiusKm > 0) qp.add('radius_km=${radiusKm.toString()}');
    final suffix = qp.isEmpty ? '' : '?${qp.join('&')}';

    final url = ApiConfig.api('/feed') + suffix;

    try {
      final res = await _client.dio.get(url);
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];

      final data = res.data;
      if (data is String) return <dynamic>[];
      if (data is Map) {
        final items = data['items'];
        if (items is List) return items;
        final wrapped = data['data'];
        if (wrapped is List) return wrapped;
      }
      if (data is List) return data;

      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  /// GET /api/locations (compat)
  Future<Map<String, dynamic>> getLocations() async {
    try {
      final data = await _client.getJson(ApiConfig.api('/locations'));
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// GET /api/heatmap (compat)
  Future<Map<String, dynamic>> getHeatmap() async {
    try {
      final data = await _client.getJson(ApiConfig.api('/heatmap'));
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<List<dynamic>> loadCachedFeed() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kCache) ?? '';
      if (raw.isEmpty) return <dynamic>[];
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<void> saveCachedFeed(List<dynamic> items) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kCache, jsonEncode(items));
    } catch (_) {}
  }
}
