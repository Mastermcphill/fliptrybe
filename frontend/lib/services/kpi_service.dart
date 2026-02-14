import 'api_client.dart';
import 'api_config.dart';

class KpiService {
  Future<Map<String, dynamic>> merchantKpis() async {
    try {
      final data =
          await ApiClient.instance.getJson(ApiConfig.api('/kpis/merchant'));
      return data is Map
          ? Map<String, dynamic>.from(data as Map)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
