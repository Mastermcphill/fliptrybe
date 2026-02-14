import 'api_client.dart';
import 'api_config.dart';

class AdminRoleService {
  AdminRoleService({ApiClient? client})
      : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<dynamic>> pending(
      {String status = 'PENDING', int limit = 50}) async {
    try {
      final uri =
          '${ApiConfig.api('/admin/role-requests')}?status=$status&limit=$limit';
      final res = await _client.dio.get(uri);
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> approve({
    required int requestId,
    String adminNote = '',
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (adminNote.trim().isNotEmpty) payload['admin_note'] = adminNote.trim();
      final res = await _client.dio.post(
          ApiConfig.api('/admin/role-requests/$requestId/approve'),
          data: payload);
      final code = res.statusCode ?? 0;
      final ok = code >= 200 && code < 300;
      if (res.data is Map<String, dynamic>) {
        final data =
            Map<String, dynamic>.from(res.data as Map<String, dynamic>);
        data['ok'] = ok;
        data['status'] = code;
        return data;
      }
      return {'ok': ok, 'status': code, 'data': res.data};
    } catch (_) {
      return {'ok': false, 'message': 'Approve failed'};
    }
  }

  Future<Map<String, dynamic>> reject({
    required int requestId,
    String reason = 'Rejected by admin',
  }) async {
    try {
      final payload = <String, dynamic>{'admin_note': reason};
      final res = await _client.dio.post(
          ApiConfig.api('/admin/role-requests/$requestId/reject'),
          data: payload);
      final code = res.statusCode ?? 0;
      final ok = code >= 200 && code < 300;
      if (res.data is Map<String, dynamic>) {
        final data =
            Map<String, dynamic>.from(res.data as Map<String, dynamic>);
        data['ok'] = ok;
        data['status'] = code;
        return data;
      }
      return {'ok': ok, 'status': code, 'data': res.data};
    } catch (_) {
      return {'ok': false, 'message': 'Reject failed'};
    }
  }
}
