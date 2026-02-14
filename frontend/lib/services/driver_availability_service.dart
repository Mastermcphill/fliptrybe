import 'api_client.dart';
import 'api_config.dart';

class DriverAvailabilityService {
  Future<Map<String, dynamic>> setAvailability(bool isAvailable) async {
    final data = await ApiClient.instance.postJson(
        ApiConfig.api('/driver/availability'), {'is_available': isAvailable});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
