import 'api_client.dart';
import 'api_config.dart';

class AdminOpsService {
  Future<Map<String, dynamic>> healthSummary() async {
    final data = await ApiClient.instance
        .getJson(ApiConfig.api('/admin/health/summary'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getFlags() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/admin/flags'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateFlags(Map<String, dynamic> flags) async {
    final data = await ApiClient.instance.dio
        .put(ApiConfig.api('/admin/flags'), data: {'flags': flags});
    final payload = data.data;
    return payload is Map
        ? Map<String, dynamic>.from(payload)
        : <String, dynamic>{};
  }
}
