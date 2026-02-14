import 'api_client.dart';
import 'api_config.dart';

class AdminAuditService {
  Future<List<dynamic>> list({String action = ""}) async {
    final qp = <String, String>{};
    if (action.trim().isNotEmpty) qp['action'] = action.trim();
    final uri = Uri.parse(ApiConfig.api('/admin/audit'))
        .replace(queryParameters: qp.isEmpty ? null : qp);
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is List ? data : <dynamic>[];
  }
}
