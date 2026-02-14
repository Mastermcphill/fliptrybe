import 'api_client.dart';
import 'api_config.dart';

class OmegaIntelligenceService {
  Future<Map<String, dynamic>> overview() async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/admin/omega/intelligence'),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> elasticitySegment({
    required String category,
    String city = 'all',
    String sellerType = 'all',
    int windowDays = 90,
  }) async {
    final url = StringBuffer('/admin/elasticity/segment?')
      ..write('category=${Uri.encodeQueryComponent(category)}')
      ..write('&city=${Uri.encodeQueryComponent(city)}')
      ..write('&seller_type=${Uri.encodeQueryComponent(sellerType)}')
      ..write('&window_days=$windowDays');
    final data = await ApiClient.instance.getJson(ApiConfig.api(url.toString()));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> fraudFlags({
    bool refresh = true,
    String status = 'open_only',
    int minScore = 30,
    int limit = 100,
    int offset = 0,
  }) async {
    final url = StringBuffer('/admin/fraud/flags?')
      ..write('refresh=${refresh ? 1 : 0}')
      ..write('&status=${Uri.encodeQueryComponent(status)}')
      ..write('&min_score=$minScore')
      ..write('&limit=$limit')
      ..write('&offset=$offset');
    final data = await ApiClient.instance.getJson(ApiConfig.api(url.toString()));
    if (data is Map && data['items'] is List) {
      return (data['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> reviewFraudFlag({
    required int fraudFlagId,
    required String status,
    String note = '',
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/fraud/$fraudFlagId/review'),
      {
        'status': status,
        'note': note,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> freezeFraudFlag({
    required int fraudFlagId,
    String note = '',
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/fraud/$fraudFlagId/freeze'),
      {'note': note},
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> crossMarketSimulate({
    required int timeHorizonDays,
    String commissionShiftCity = '',
    int commissionShiftBps = 0,
    String promoCity = '',
    int promoDiscountBps = 0,
    int payoutDelayAdjustmentDays = 0,
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/liquidity/cross-market-simulate'),
      {
        'time_horizon_days': timeHorizonDays,
        'commission_shift_city': commissionShiftCity,
        'commission_shift_bps': commissionShiftBps,
        'promo_city': promoCity,
        'promo_discount_bps': promoDiscountBps,
        'payout_delay_adjustment_days': payoutDelayAdjustmentDays,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> expansionSimulate({
    required String targetCity,
    required int assumedListings,
    required int assumedDailyGmvMinor,
    required int averageOrderValueMinor,
    required int marketingBudgetMinor,
    required int estimatedCommissionBps,
    required int operatingCostDailyMinor,
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/expansion/simulate'),
      {
        'target_city': targetCity,
        'assumed_listings': assumedListings,
        'assumed_daily_gmv_minor': assumedDailyGmvMinor,
        'average_order_value_minor': averageOrderValueMinor,
        'marketing_budget_minor': marketingBudgetMinor,
        'estimated_commission_bps': estimatedCommissionBps,
        'operating_cost_daily_minor': operatingCostDailyMinor,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
