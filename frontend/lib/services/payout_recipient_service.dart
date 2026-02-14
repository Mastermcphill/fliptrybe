import 'api_client.dart';
import 'api_config.dart';

class PayoutRecipientService {
  Future<Map<String, dynamic>> getRecipient() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/payout/recipient'));
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> setRecipient(
      {required String recipientCode, String provider = 'paystack'}) async {
    final data = await ApiClient.instance.postJson(
        ApiConfig.api('/payout/recipient'),
        {'provider': provider, 'recipient_code': recipientCode});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
