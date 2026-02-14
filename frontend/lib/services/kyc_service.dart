import 'api_client.dart';
import 'api_config.dart';

class KycService {
  KycService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<Map<String, dynamic>> status() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/kyc/status'));
      final data = res.data;
      if (data is Map && data['kyc'] is Map)
        return Map<String, dynamic>.from(data['kyc'] as Map);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, dynamic>?> submit(
      {required String fullName,
      required String idType,
      required String idNumber}) async {
    try {
      final res = await _client.dio.post(ApiConfig.api('/kyc/submit'), data: {
        'full_name': fullName,
        'id_type': idType,
        'id_number': idNumber,
      });
      final data = res.data;
      if (data is Map && data['kyc'] is Map)
        return Map<String, dynamic>.from(data['kyc'] as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> adminSet(
      {required int userId, required String status, String note = ''}) async {
    try {
      final res = await _client.dio.post(ApiConfig.api('/kyc/admin/set'),
          data: {'user_id': userId, 'status': status, 'note': note});
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> adminPending() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/kyc/admin/pending'));
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }
}
