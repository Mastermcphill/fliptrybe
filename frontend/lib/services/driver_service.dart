import 'api_client.dart';
import 'api_config.dart';

class DriverService {
  Future<List<dynamic>> getJobs() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api("/driver/jobs"));
    return data is List ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> acceptJob({required int jobId}) async {
    return await ApiClient.instance.postJson(
      ApiConfig.api("/driver/jobs/$jobId/accept"),
      {},
    );
  }

  Future<Map<String, dynamic>> updateStatus(
      {required int jobId, required String status}) async {
    return await ApiClient.instance.postJson(
      ApiConfig.api("/driver/jobs/$jobId/status"),
      {"status": status},
    );
  }
}
