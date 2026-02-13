import 'api_client.dart';
import 'api_config.dart';

class CategoryService {
  CategoryService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> categoriesTree() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/public/categories'));
      final data = res.data;
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, List<Map<String, dynamic>>>> filters({
    int? categoryId,
    int? brandId,
  }) async {
    final params = <String, String>{};
    if (categoryId != null && categoryId > 0) {
      params['category_id'] = '$categoryId';
    }
    if (brandId != null && brandId > 0) {
      params['brand_id'] = '$brandId';
    }
    try {
      final uri = Uri(path: '/public/filters', queryParameters: params);
      final res = await _client.dio.get(ApiConfig.api(uri.toString()));
      final data = res.data;
      if (data is Map) {
        final brands = (data['brands'] is List)
            ? (data['brands'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
        final models = (data['models'] is List)
            ? (data['models'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
        return <String, List<Map<String, dynamic>>>{
          'brands': brands,
          'models': models,
        };
      }
    } catch (_) {}
    return const <String, List<Map<String, dynamic>>>{
      'brands': <Map<String, dynamic>>[],
      'models': <Map<String, dynamic>>[],
    };
  }
}
