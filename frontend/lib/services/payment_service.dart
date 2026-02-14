import 'api_client.dart';
import 'api_config.dart';

class PaymentService {
  Future<Map<String, dynamic>> initialize(
      {required double amount,
      String purpose = 'topup',
      int? orderId,
      String paymentMethod = 'paystack_card'}) async {
    final payload = <String, dynamic>{
      'amount': amount,
      'purpose': purpose,
      'payment_method': paymentMethod,
    };
    if (orderId != null) {
      payload['order_id'] = orderId;
    }
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/payments/initialize'),
      payload,
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> status({required int orderId}) async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/payments/status?order_id=$orderId'),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> manualInstructions() async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/public/manual-payment-instructions'),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> availableMethods(
      {String scope = 'order'}) async {
    final safeScope = (scope == 'shortlet') ? 'shortlet' : 'order';
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/payments/methods?scope=$safeScope'),
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> submitManualProof({
    required int paymentIntentId,
    String bankTxnReference = '',
    String note = '',
  }) async {
    final payload = <String, dynamic>{};
    if (bankTxnReference.trim().isNotEmpty) {
      payload['bank_txn_reference'] = bankTxnReference.trim();
    }
    if (note.trim().isNotEmpty) {
      payload['note'] = note.trim();
    }
    final data = await ApiClient.instance.postJson(
      ApiConfig.api('/payments/manual/$paymentIntentId/proof'),
      payload,
    );
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> confirmSim({required String reference}) async {
    // Backend route `/api/payments/confirm` is not available in current inventory.
    // Return a deterministic, explicit response instead of generating avoidable 404s.
    return <String, dynamic>{
      'ok': false,
      'error': 'NOT_AVAILABLE',
      'message': 'Payment confirm endpoint is not available.',
      'reference': reference,
    };
  }
}
