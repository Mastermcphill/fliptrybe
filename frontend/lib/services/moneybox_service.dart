import 'api_client.dart';
import 'api_config.dart';

class MoneyBoxService {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> status() async {
    final data = await _client.getJson(ApiConfig.api('/moneybox/status'));
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> openTier(int tier) async {
    final data =
        await _client.postJson(ApiConfig.api('/moneybox/open'), {'tier': tier});
    return _asMap(data);
  }

  Future<Map<String, dynamic>> setTier(int tier) async {
    final data =
        await _client.postJson(ApiConfig.api('/moneybox/tier'), {'tier': tier});
    return _asMap(data);
  }

  Future<Map<String, dynamic>> autosaveSettings() async {
    final data =
        await _client.getJson(ApiConfig.api('/moneybox/autosave/settings'));
    return _asMap(data);
  }

  Future<Map<String, dynamic>> updateAutosaveSettings({
    required bool enabled,
    required int percent,
  }) async {
    final safePercent = percent < 1
        ? 1
        : percent > 30
            ? 30
            : percent;
    final data = await _client.postJson(
      ApiConfig.api('/moneybox/autosave/settings'),
      {
        'autosave_enabled': enabled,
        'autosave_percent': safePercent,
      },
    );
    return _asMap(data);
  }

  Future<Map<String, dynamic>> setAutosave(int percent) async {
    final data = await _client.postJson(ApiConfig.api('/moneybox/autosave'), {
      'enabled': true,
      'percent': percent,
    });
    return _asMap(data);
  }

  Future<Map<String, dynamic>> withdraw({double? amount}) async {
    final body = <String, dynamic>{};
    if (amount != null) body['amount'] = amount;
    final data =
        await _client.postJson(ApiConfig.api('/moneybox/withdraw'), body);
    return _asMap(data);
  }

  Future<List<dynamic>> ledger() async {
    final data = await _client.getJson(ApiConfig.api('/moneybox/ledger'));
    if (data is Map && data['items'] is List) {
      return data['items'] as List;
    }
    return <dynamic>[];
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }
}
