import 'api_client.dart';
import 'api_config.dart';

class SettingsService {
  final ApiClient _client = ApiClient.instance;

  Future<Map<String, dynamic>> getSettings() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/settings'));
      final data = res.data;
      if (data is Map && data['settings'] is Map)
        return Map<String, dynamic>.from(data['settings'] as Map);
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<bool> updateSettings({
    bool? notifInApp,
    bool? notifSms,
    bool? notifWhatsapp,
    bool? darkMode,
    String? themeMode,
    String? backgroundPalette,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (notifInApp != null) payload['notif_in_app'] = notifInApp;
      if (notifSms != null) payload['notif_sms'] = notifSms;
      if (notifWhatsapp != null) payload['notif_whatsapp'] = notifWhatsapp;
      if (darkMode != null) payload['dark_mode'] = darkMode;
      if ((themeMode ?? '').trim().isNotEmpty) {
        payload['theme_mode'] = themeMode!.trim().toLowerCase();
      }
      if ((backgroundPalette ?? '').trim().isNotEmpty) {
        payload['background_palette'] = backgroundPalette!.trim().toLowerCase();
      }
      final res = await _client.dio.post(
        ApiConfig.api('/settings'),
        data: payload,
      );
      final code = res.statusCode ?? 0;
      return code >= 200 && code < 300;
    } catch (_) {
      return false;
    }
  }
}
