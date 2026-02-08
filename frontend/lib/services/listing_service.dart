import 'api_client.dart';
import 'api_config.dart';

class ListingService {
  final ApiClient _client = ApiClient.instance;

  Future<List<dynamic>> listListings() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/listings'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is List) return data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> listMyListings() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/merchant/listings'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <dynamic>[];
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      if (data is List) return data;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>?> createListing({
    required String title,
    String description = '',
    double price = 0,
    String? imagePath,
  }) async {
    try {
      // Prefer multipart via ApiClient helper if file path is provided
      if (imagePath != null && imagePath.trim().isNotEmpty) {
        final res = await _client.postMultipart(
          ApiConfig.api('/listings'),
          fields: {
            'title': title,
            'description': description,
            'price': price.toString(),
          },
          fileField: 'image',
          filePath: imagePath,
        );
        final data = res;
        if (data is Map && data['listing'] is Map) return Map<String, dynamic>.from(data['listing']);
        return null;
      }

      final res = await _client.dio.post(ApiConfig.api('/listings'), data: {
        'title': title,
        'description': description,
        'price': price,
      });
      final data = res.data;
      if (data is Map && data['listing'] is Map) return Map<String, dynamic>.from(data['listing']);
      return null;
    } catch (_) {
      return null;
    }
  }
}
