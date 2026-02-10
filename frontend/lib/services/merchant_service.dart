import 'api_client.dart';
import 'api_config.dart';

class MerchantService {
  MerchantService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<dynamic>> getLeaderboard() async {
    try {
      final res =
          await _client.dio.get(ApiConfig.api('/leaderboards') + '?limit=50');
      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : <dynamic>[];
      return items.map((raw) {
        if (raw is! Map) return <String, dynamic>{};
        final m = Map<String, dynamic>.from(raw as Map);
        return <String, dynamic>{
          'user_id': m['user_id'],
          'name': (m['shop_name'] ?? '').toString().trim().isEmpty
              ? 'Merchant #${m['user_id'] ?? '-'}'
              : (m['shop_name'] ?? '').toString(),
          'score': m['score'] ?? 0,
          'orders': m['total_orders'] ?? 0,
          'listings': m['listings_count'] ?? 0,
          'revenue_gross': m['total_sales'] ?? 0,
          'state': m['state'] ?? '',
          'city': m['city'] ?? '',
        };
      }).toList();
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> getKpis() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/kpis/merchant'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<List<dynamic>> topMerchants({int limit = 20}) async {
    try {
      final res = await _client.dio
          .get(ApiConfig.api('/merchants/top') + '?limit=$limit');
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> merchantDetail(int userId) async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/merchants/$userId'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> followMerchant(int userId) async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/merchants/$userId/follow'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> unfollowMerchant(int userId) async {
    try {
      final res =
          await _client.dio.delete(ApiConfig.api('/merchants/$userId/follow'));
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<bool> simulateSale(
      {required int userId, required double amount}) async {
    try {
      final res = await _client.dio.post(
          ApiConfig.api('/merchants/$userId/simulate-sale'),
          data: {'amount': amount});
      final code = res.statusCode ?? 0;
      return code == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> addReview(
      {required int userId,
      required int rating,
      required String comment,
      String raterName = 'Anonymous'}) async {
    try {
      final res = await _client.dio
          .post(ApiConfig.api('/merchants/$userId/review'), data: {
        'rating': rating,
        'comment': comment,
        'rater_name': raterName
      });
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }

  Future<Map<String, dynamic>> updateProfile({
    required String shopName,
    required String category,
    required String state,
    required String city,
    String locality = '',
    String lga = '',
  }) async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/merchants/profile'), data: {
        'shop_name': shopName,
        'shop_category': category,
        'state': state,
        'city': city,
        'locality': locality,
        'lga': lga,
      });
      final data = res.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return <String, dynamic>{'ok': false};
    } catch (_) {
      return <String, dynamic>{'ok': false};
    }
  }
}
