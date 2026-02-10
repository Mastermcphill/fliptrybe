import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';

class ListingService {
  final ApiClient _client = ApiClient.instance;

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

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

  Future<Map<String, dynamic>> createListing({
    required String title,
    String description = '',
    double price = 0,
    String? imagePath,
  }) async {
    try {
      final url = ApiConfig.api('/listings');
      if (imagePath != null && imagePath.trim().isNotEmpty) {
        final normalized = imagePath.replaceAll('\\', '/');
        final filename = normalized.split('/').last;
        final form = FormData.fromMap({
          'title': title,
          'description': description,
          'price': price.toString(),
          'image': await MultipartFile.fromFile(imagePath, filename: filename),
        });
        final res = await _client.dio.post(url, data: form);
        final data = _asMap(res.data);
        final status = res.statusCode ?? 0;
        data['status'] = status;
        data['ok'] = status >= 200 && status < 300 && data['ok'] != false;
        if (data['listing'] is Map) {
          data['listing'] = Map<String, dynamic>.from(data['listing'] as Map);
        }
        return data;
      }

      final res = await _client.dio.post(url, data: {
        'title': title,
        'description': description,
        'price': price,
      });
      final data = _asMap(res.data);
      final status = res.statusCode ?? 0;
      data['status'] = status;
      data['ok'] = status >= 200 && status < 300 && data['ok'] != false;
      if (data['listing'] is Map) {
        data['listing'] = Map<String, dynamic>.from(data['listing'] as Map);
      }
      return data;
    } on DioException catch (e) {
      final data = _asMap(e.response?.data);
      final status = e.response?.statusCode ?? 0;
      data['status'] = status;
      data['ok'] = false;
      if ((data['message'] ?? '').toString().trim().isEmpty) {
        data['message'] = 'Failed to upload';
      }
      return data;
    } catch (e) {
      return {
        'ok': false,
        'message': 'Failed to upload',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> getListing(int listingId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/listings/$listingId'));
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) return <String, dynamic>{};
      return _asMap(res.data);
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
