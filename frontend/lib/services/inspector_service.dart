import 'api_client.dart';
import 'api_config.dart';

class InspectorService {
  final ApiClient _client = ApiClient.instance;
  String? lastInfo;

  Future<List<dynamic>> assignments() async {
    lastInfo = null;
    try {
      // Endpoint is not available yet in backend route inventory.
      // Keep UX deterministic: empty list + explicit info message.
      await _client.getJson(ApiConfig.api('/inspectors/me/profile'));
      lastInfo = 'Inspection assignments are not available yet.';
      return <dynamic>[];
    } catch (_) {
      lastInfo = 'Inspector assignments are currently unavailable.';
      return <dynamic>[];
    }
  }

  Future<bool> submitReport(int assignmentId,
      {required String verdict, required String report}) async {
    lastInfo = 'Inspector report submission is not available yet.';
    return false;
  }
}
