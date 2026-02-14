import 'api_client.dart';
import 'api_config.dart';

class CommissionPolicyService {
  Future<List<Map<String, dynamic>>> listPolicies({String? status}) async {
    final uri = Uri.parse(ApiConfig.api('/admin/commission/policies')).replace(
      queryParameters: (status != null && status.trim().isNotEmpty)
          ? <String, String>{'status': status.trim()}
          : null,
    );
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

  Future<Map<String, dynamic>> createDraft({
    required String name,
    String notes = '',
  }) async {
    final raw = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/commission/policies'),
      <String, dynamic>{
        'name': name,
        'notes': notes,
      },
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> addRule({
    required int policyId,
    required String appliesTo,
    required String sellerType,
    required int baseRateBps,
    String city = '',
    int? minFeeMinor,
    int? maxFeeMinor,
    int? promoDiscountBps,
    String? startsAtIso,
    String? endsAtIso,
  }) async {
    final raw = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/commission/policies/$policyId/rules'),
      <String, dynamic>{
        'applies_to': appliesTo,
        'seller_type': sellerType,
        'city': city,
        'base_rate_bps': baseRateBps,
        if (minFeeMinor != null) 'min_fee_minor': minFeeMinor,
        if (maxFeeMinor != null) 'max_fee_minor': maxFeeMinor,
        if (promoDiscountBps != null) 'promo_discount_bps': promoDiscountBps,
        if (startsAtIso != null && startsAtIso.trim().isNotEmpty)
          'starts_at': startsAtIso.trim(),
        if (endsAtIso != null && endsAtIso.trim().isNotEmpty)
          'ends_at': endsAtIso.trim(),
      },
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> activate(int policyId) async {
    final raw = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/commission/policies/$policyId/activate'),
      const <String, dynamic>{},
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> archive(int policyId) async {
    final raw = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/commission/policies/$policyId/archive'),
      const <String, dynamic>{},
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> preview({
    required String appliesTo,
    required String sellerType,
    required String city,
    required int amountMinor,
  }) async {
    final uri = Uri.parse(ApiConfig.api('/admin/commission/preview')).replace(
      queryParameters: <String, String>{
        'applies_to': appliesTo,
        'seller_type': sellerType,
        'city': city,
        'amount_minor': '$amountMinor',
      },
    );
    final raw = await ApiClient.instance.getJson(uri.toString());
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'ok': false};
  }
}
