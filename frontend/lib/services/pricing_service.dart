import 'api_client.dart';
import 'api_config.dart';

class PricingService {
  Future<Map<String, dynamic>> suggest({
    required String category,
    required String city,
    required String itemType,
    required String condition,
    required int currentPriceMinor,
    int? durationNights,
    Map<String, dynamic>? attributes,
  }) async {
    final payload = <String, dynamic>{
      'category': category,
      'city': city,
      'item_type': itemType,
      'condition': condition,
      'current_price_minor': currentPriceMinor,
      if (durationNights != null) 'duration_nights': durationNights,
      if (attributes != null) 'attributes': attributes,
    };
    final raw =
        await ApiClient.instance.postJson(ApiConfig.api('/pricing/suggest'), payload);
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }

  Future<List<Map<String, dynamic>>> adminBenchmarks({
    String? category,
    String? city,
    int limit = 120,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (category != null && category.trim().isNotEmpty) 'category': category.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
    };
    final uri = Uri.parse(ApiConfig.api('/admin/pricing/benchmarks'))
        .replace(queryParameters: query);
    final raw = await ApiClient.instance.getJson(uri.toString());
    final items = (raw is Map ? raw['items'] : null);
    if (items is List) {
      return items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }
}
