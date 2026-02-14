import 'api_client.dart';
import 'api_config.dart';

class TopupService {
  Future<Map<String, dynamic>> initialize(double amount) async {
    final data = await ApiClient.instance.postJson(
        ApiConfig.api('/payments/initialize'),
        {'amount': amount, 'purpose': 'topup'});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
