import 'api_client.dart';
import 'api_config.dart';

class ReferralService {
  Future<Map<String, dynamic>> code() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/referral/code'));
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  Future<Map<String, dynamic>> stats() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/referral/stats'));
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  Future<Map<String, dynamic>> history({int limit = 50, int offset = 0}) async {
    final uri = Uri.parse(ApiConfig.api('/referral/history')).replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }

  Future<Map<String, dynamic>> apply(String code) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/referral/apply'),
      <String, dynamic>{'referral_code': code.trim()},
    );
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{});
  }
}
