import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_config.dart';

class AdminBroadcastService {
  ApiClient get client => _client;
  AdminBroadcastService({ApiClient? client})
      : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<bool> processQueue() async {
    try {
      final res =
          await _client.dio.post(ApiConfig.api('/admin/notifications/process'));
      final code = res.statusCode ?? 0;
      return code == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> broadcast({
    required String title,
    required String message,
    String channel = 'in_app',
    String state = '',
    String city = '',
  }) async {
    try {
      final res = await _client.dio.post(
        ApiConfig.api('/admin/notifications/broadcast'),
        data: {
          'title': title,
          'message': message,
          'channel': channel,
          'state': state,
          'city': city,
        },
      );
      final code = res.statusCode ?? 0;
      return code == 201 || code == 200;
    } catch (_) {
      return false;
    }
  }
}
