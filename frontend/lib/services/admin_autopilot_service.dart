import 'api_client.dart';
import 'api_config.dart';

class AdminAutopilotService {
  Future<Map<String, dynamic>> status() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/admin/autopilot'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> toggle({required bool enabled}) async {
    final data = await ApiClient.instance.postJson(
        ApiConfig.api('/admin/autopilot/toggle'), {'enabled': enabled});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> tick() async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/autopilot/tick'), {});
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

  Future<Map<String, dynamic>> getPaymentsSettings() async {
    final data = await ApiClient.instance
        .getJson(ApiConfig.api('/admin/settings/payments'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setPaymentsMode({required String mode}) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/settings/payments'),
      {'mode': mode},
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<dynamic>> listManualPayments(
      {String q = '', int limit = 50, int offset = 0}) async {
    final query = StringBuffer(
        '/admin/payments/manual/pending?limit=$limit&offset=$offset');
    if (q.trim().isNotEmpty) {
      query.write('&q=${Uri.encodeQueryComponent(q.trim())}');
    }
    final data =
        await ApiClient.instance.getJson(ApiConfig.api(query.toString()));
    if (data is Map && data['items'] is List)
      return data['items'] as List<dynamic>;
    return <dynamic>[];
  }

  Future<Map<String, dynamic>> markManualPaid({
    required int orderId,
    int? amountMinor,
    String reference = '',
    String note = '',
  }) async {
    final body = <String, dynamic>{
      'order_id': orderId,
    };
    if (amountMinor != null) body['amount_minor'] = amountMinor;
    if (reference.trim().isNotEmpty) body['reference'] = reference.trim();
    if (note.trim().isNotEmpty) body['note'] = note.trim();
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/payments/manual/mark-paid'), body);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
