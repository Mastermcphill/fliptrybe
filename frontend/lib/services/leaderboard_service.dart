import 'api_client.dart';
import 'api_config.dart';

class LeaderboardService {
  LeaderboardService({ApiClient? client})
      : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<dynamic>> ranked({String? state, int limit = 20}) async {
    try {
      final qp = <String, String>{'limit': '$limit'};
      if (state != null && state.trim().isNotEmpty) {
        qp['state'] = state.trim();
      }
      final uri = Uri.parse(ApiConfig.api('/leaderboards'))
          .replace(queryParameters: qp);
      final res = await _client.dio.get(uri.toString());
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> featured() async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/leaderboards/featured'));
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> byStates({int limit = 10}) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/leaderboards/states') + '?limit=$limit');
      final data = res.data;
      if (data is Map && data['items'] is Map)
        return Map<String, dynamic>.from(data['items']);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>> byCities({int limit = 10}) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/leaderboards/cities') + '?limit=$limit');
      final data = res.data;
      if (data is Map && data['items'] is Map)
        return Map<String, dynamic>.from(data['items']);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
