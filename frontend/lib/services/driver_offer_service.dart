import 'api_client.dart';
import 'api_config.dart';

class DriverOfferService {
  Future<List<dynamic>> myOffers() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/driver/offers'));
    return data is List ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>> accept(int offerId) async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/driver/offers/$offerId/accept'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> reject(int offerId) async {
    final data = await ApiClient.instance
        .postJson(ApiConfig.api('/driver/offers/$offerId/reject'), {});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
