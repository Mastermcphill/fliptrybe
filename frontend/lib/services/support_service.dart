import 'api_client.dart';
import 'api_config.dart';

class SupportService {
  SupportService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  Future<List<dynamic>> listTickets({bool all = false}) async {
    final url = ApiConfig.api('/support/tickets') + (all ? '?all=1' : '');
    try {
      final res = await _client.dio.get(url);
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> createTicket(
      {required String subject, required String message}) async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/support/tickets'), data: {
        'subject': subject,
        'message': message,
      });
      final data = _asMap(res.data);
      final status = res.statusCode ?? 0;
      data['ok'] = status >= 200 && status < 300 && data['ok'] != false;
      data['status'] = status;
      if (data['ticket'] is Map) {
        data['ticket'] = Map<String, dynamic>.from(data['ticket'] as Map);
      }
      return data;
    } catch (e) {
      return {
        'ok': false,
        'message': 'Request failed',
        'error': e.toString(),
      };
    }
  }

  Future<bool> updateStatus(int ticketId, String status) async {
    try {
      final res = await _client.dio.post(
          ApiConfig.api('/support/tickets/$ticketId/status'),
          data: {'status': status});
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> adminThreadMessages(int threadId) async {
    try {
      final res = await _client.dio.get(
        ApiConfig.api('/admin/support/threads/$threadId/messages'),
      );
      final data = _asMap(res.data);
      final raw = data['items'];
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<Map<String, dynamic>> adminReply({
    required int threadId,
    required String body,
  }) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/admin/support/threads/$threadId/messages'),
        data: {'body': body},
      );
      final data = _asMap(res.data);
      final status = res.statusCode ?? 0;
      data['ok'] = status >= 200 && status < 300 && data['ok'] != false;
      data['status'] = status;
      if (data['message'] is Map) {
        data['message'] = Map<String, dynamic>.from(data['message'] as Map);
      }
      return data;
    } catch (e) {
      return {
        'ok': false,
        'message': 'Request failed',
        'error': e.toString(),
      };
    }
  }
}
