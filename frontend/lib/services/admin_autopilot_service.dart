import 'api_client.dart';
import 'api_config.dart';

class AdminAutopilotService {
  Future<Map<String, dynamic>> status() async {
    final data = await ApiClient.instance.getJson(ApiConfig.api('/admin/autopilot'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> toggle({required bool enabled}) async {
    final data = await ApiClient.instance.postJson(ApiConfig.api('/admin/autopilot/toggle'), {'enabled': enabled});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> tick() async {
    final data = await ApiClient.instance.postJson(ApiConfig.api('/admin/autopilot/tick'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateSettings({
    required String paymentsProvider,
    required String integrationsMode,
    required bool paystackEnabled,
    required bool termiiEnabledSms,
    required bool termiiEnabledWa,
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/autopilot/settings'),
      {
        'payments_provider': paymentsProvider,
        'integrations_mode': integrationsMode,
        'paystack_enabled': paystackEnabled,
        'termii_enabled_sms': termiiEnabledSms,
        'termii_enabled_wa': termiiEnabledWa,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
