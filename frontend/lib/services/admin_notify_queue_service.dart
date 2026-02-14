import 'api_client.dart';
import 'api_config.dart';

class AdminNotifyQueueService {
  Future<List<dynamic>> list({String channel = "", String status = ""}) async {
    final qp = <String, String>{};
    if (channel.trim().isNotEmpty) qp['channel'] = channel.trim();
    if (status.trim().isNotEmpty) qp['status'] = status.trim();
    final uri = Uri.parse(ApiConfig.api('/admin/notify-queue'))
        .replace(queryParameters: qp.isEmpty ? null : qp);
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is List ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> markSent(int id) async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/notify-queue/$id/mark-sent'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> requeue(int id) async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/notify-queue/$id/requeue'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> retryNow(int id) async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/notify-queue/$id/retry-now'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> requeueDead({String channel = ''}) async {
    final qp = <String, String>{};
    if (channel.trim().isNotEmpty) qp['channel'] = channel.trim();
    final uri = Uri.parse(ApiConfig.api('/admin/notify-queue/requeue-dead'))
        .replace(queryParameters: qp.isEmpty ? null : qp);
    final data = await ApiClient.instance.postJson(uri.toString(), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
