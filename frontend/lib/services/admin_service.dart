import 'api_client.dart';
import 'api_config.dart';

class AdminService {
  Future<Map<String, dynamic>> overview() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api("/admin/summary"));
    if (data is Map<String, dynamic>) {
      // Backward-compat for legacy screens expecting `counts`.
      if (data['counts'] == null && data['stats'] is Map) {
        data['counts'] = Map<String, dynamic>.from(data['stats'] as Map);
      }
      return data;
    }
    if (data is Map) {
      final cast = data.map((k, v) => MapEntry('$k', v));
      if (cast['counts'] == null && cast['stats'] is Map) {
        cast['counts'] = Map<String, dynamic>.from(cast['stats'] as Map);
      }
      return cast;
    }
    return <String, dynamic>{'ok': false, 'counts': <String, dynamic>{}};
  }

  Future<Map<String, dynamic>> disableUser(
      {required int userId, String reason = "disabled by admin"}) async {
    return await ApiClient.instance.postJson(
      ApiConfig.api("/admin/users/$userId/disable"),
      {"reason": reason},
    );
  }

  Future<Map<String, dynamic>> disableListing(
      {required int listingId, String reason = "disabled by admin"}) async {
    return await ApiClient.instance.postJson(
      ApiConfig.api("/admin/listings/$listingId/disable"),
      {"reason": reason},
    );
  }
}
