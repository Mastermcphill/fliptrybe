import 'api_client.dart';
import 'api_config.dart';

class DriverDirectoryService {
  Future<List<dynamic>> listDrivers(
      {String state = '', String city = '', String locality = ''}) async {
    final q = <String, String>{};
    if (state.trim().isNotEmpty) q['state'] = state.trim();
    if (city.trim().isNotEmpty) q['city'] = city.trim();
    if (locality.trim().isNotEmpty) q['locality'] = locality.trim();

    final uri = Uri.parse(ApiConfig.api('/merchant/drivers'))
        .replace(queryParameters: q.isEmpty ? null : q);
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is List ? data : <dynamic>[];
  }

  Future<Map<String, dynamic>?> activeJob() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/driver/active'));
    if (data is Map && data['job'] is Map) {
      return Map<String, dynamic>.from(data['job'] as Map);
    }
    return null;
  }

  Future<Map<String, dynamic>?> getMyDriverProfile() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/driver/profile'));
    if (data is Map && data['profile'] is Map) {
      return Map<String, dynamic>.from(data['profile'] as Map);
    }
    return null;
  }

  Future<bool> saveMyDriverProfile({
    required String phone,
    required String vehicleType,
    required String plateNumber,
    required String state,
    required String city,
    required String locality,
    bool isActive = true,
  }) async {
    final res =
        await ApiClient.instance.postJson(ApiConfig.api('/driver/profile'), {
      'phone': phone,
      'vehicle_type': vehicleType,
      'plate_number': plateNumber,
      'state': state,
      'city': city,
      'locality': locality,
      'is_active': isActive,
    });
    return res is Map && res['ok'] == true;
  }
}
