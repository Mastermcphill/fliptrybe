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
    String? searchV2Mode,
    bool? paymentsAllowLegacyFallback,
    bool? otelEnabled,
    bool? rateLimitEnabled,
  }) async {
    final body = <String, dynamic>{
      'payments_provider': paymentsProvider,
      'integrations_mode': integrationsMode,
      'paystack_enabled': paystackEnabled,
      'termii_enabled_sms': termiiEnabledSms,
      'termii_enabled_wa': termiiEnabledWa,
    };
    if (searchV2Mode != null) body['search_v2_mode'] = searchV2Mode;
    if (paymentsAllowLegacyFallback != null) {
      body['payments_allow_legacy_fallback'] = paymentsAllowLegacyFallback;
    }
    if (otelEnabled != null) body['otel_enabled'] = otelEnabled;
    if (rateLimitEnabled != null) body['rate_limit_enabled'] = rateLimitEnabled;
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/autopilot/settings'),
      body,
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getPaymentsSettings() async {
    final data = await ApiClient.instance
        .getJson(ApiConfig.api('/admin/settings/payments'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getPaymentsMode() async {
    final data = await ApiClient.instance.getJson(ApiConfig.api('/admin/payments/mode'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setPaymentsMode({
    required String mode,
    String? manualPaymentBankName,
    String? manualPaymentAccountNumber,
    String? manualPaymentAccountName,
    String? manualPaymentNote,
    int? manualPaymentSlaMinutes,
  }) async {
    final body = <String, dynamic>{'mode': mode};
    if (manualPaymentBankName != null) body['manual_payment_bank_name'] = manualPaymentBankName;
    if (manualPaymentAccountNumber != null) body['manual_payment_account_number'] = manualPaymentAccountNumber;
    if (manualPaymentAccountName != null) body['manual_payment_account_name'] = manualPaymentAccountName;
    if (manualPaymentNote != null) body['manual_payment_note'] = manualPaymentNote;
    if (manualPaymentSlaMinutes != null) body['manual_payment_sla_minutes'] = manualPaymentSlaMinutes;
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/payments/mode'),
      body,
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> savePaymentsSettings({
    required String mode,
    required String manualPaymentBankName,
    required String manualPaymentAccountNumber,
    required String manualPaymentAccountName,
    required String manualPaymentNote,
    required int manualPaymentSlaMinutes,
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/settings/payments'),
      {
        'mode': mode,
        'manual_payment_bank_name': manualPaymentBankName,
        'manual_payment_account_number': manualPaymentAccountNumber,
        'manual_payment_account_name': manualPaymentAccountName,
        'manual_payment_note': manualPaymentNote,
        'manual_payment_sla_minutes': manualPaymentSlaMinutes,
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<dynamic>> listManualPayments(
      {String q = '', String status = 'manual_pending', int limit = 50, int offset = 0}) async {
    final query = StringBuffer(
        '/admin/payments/manual/queue?limit=$limit&offset=$offset&status=${Uri.encodeQueryComponent(status)}');
    if (q.trim().isNotEmpty) {
      query.write('&q=${Uri.encodeQueryComponent(q.trim())}');
    }
    final data =
        await ApiClient.instance.getJson(ApiConfig.api(query.toString()));
    if (data is Map && data['items'] is List)
      return data['items'] as List<dynamic>;
    return <dynamic>[];
  }

  Future<Map<String, dynamic>> getManualPaymentDetails({
    required int paymentIntentId,
  }) async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/admin/payments/manual/$paymentIntentId'),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> markManualPaid({
    required int paymentIntentId,
    int? amountMinor,
    String bankTxnReference = '',
    String note = '',
  }) async {
    final body = <String, dynamic>{
      'payment_intent_id': paymentIntentId,
    };
    if (amountMinor != null) body['amount_minor'] = amountMinor;
    if (bankTxnReference.trim().isNotEmpty) {
      body['bank_txn_reference'] = bankTxnReference.trim();
    }
    if (note.trim().isNotEmpty) body['note'] = note.trim();
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/admin/payments/manual/mark-paid'), body);
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> rejectManualPayment({
    required int paymentIntentId,
    required String reason,
  }) async {
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/payments/manual/reject'),
      {
        'payment_intent_id': paymentIntentId,
        'reason': reason.trim(),
      },
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
