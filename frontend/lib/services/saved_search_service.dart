import 'api_client.dart';
import 'api_config.dart';

class SavedSearchService {
  SavedSearchService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asItems(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> list({String vertical = ''}) async {
    try {
      final params = <String, dynamic>{};
      if (vertical.trim().isNotEmpty) {
        params['vertical'] = vertical.trim();
      }
      final res = await _client.dio.get(
        ApiConfig.api('/saved-searches'),
        queryParameters: params,
      );
      final payload = _asMap(res.data);
      return _asItems(payload['items']);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> create({
    required String name,
    required String vertical,
    required Map<String, dynamic> queryJson,
  }) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/saved-searches'),
        data: <String, dynamic>{
          'name': name.trim(),
          'vertical': vertical.trim(),
          'query_json': queryJson,
        },
      );
      final payload = _asMap(res.data);
      payload['ok'] = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      return payload;
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': 'Unable to save search: $e'};
    }
  }

  Future<Map<String, dynamic>> update({
    required int id,
    String? name,
    String? vertical,
    Map<String, dynamic>? queryJson,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (name != null) data['name'] = name.trim();
      if (vertical != null) data['vertical'] = vertical.trim();
      if (queryJson != null) data['query_json'] = queryJson;
      final res = await _client.dio.put(
        ApiConfig.api('/saved-searches/$id'),
        data: data,
      );
      final payload = _asMap(res.data);
      payload['ok'] = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      return payload;
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': 'Unable to update search: $e'};
    }
  }

  Future<Map<String, dynamic>> use(int id) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/saved-searches/$id/use'),
        data: const <String, dynamic>{},
      );
      final payload = _asMap(res.data);
      payload['ok'] = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      return payload;
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': 'Unable to apply search: $e'};
    }
  }

  Future<Map<String, dynamic>> remove(int id) async {
    try {
      final res = await _client.dio.delete(ApiConfig.api('/saved-searches/$id'));
      final payload = _asMap(res.data);
      payload['ok'] = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      return payload;
    } catch (e) {
      return <String, dynamic>{'ok': false, 'message': 'Unable to delete search: $e'};
    }
  }
}

