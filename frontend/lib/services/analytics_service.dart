import 'api_client.dart';
import 'api_config.dart';

class AnalyticsService {
  Future<Map<String, dynamic>> myAnalytics({int days = 14}) async {
    final uri = Uri.parse(ApiConfig.api('/wallet/analytics'))
        .replace(queryParameters: {'days': days.toString()});
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
