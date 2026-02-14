import 'api_client.dart';
import 'api_config.dart';

class CommissionService {
  Future<List<dynamic>> listRules(
      {String kind = "", String state = "", String category = ""}) async {
    final qp = <String, String>{};
    if (kind.trim().isNotEmpty) qp["kind"] = kind.trim();
    if (state.trim().isNotEmpty) qp["state"] = state.trim();
    if (category.trim().isNotEmpty) qp["category"] = category.trim();

    final uri = Uri.parse(ApiConfig.api("/admin/commission"))
        .replace(queryParameters: qp.isEmpty ? null : qp);
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is List ? data : <dynamic>[];
  }

  Future<bool> upsertRule({
    required String kind,
    String state = "",
    String category = "",
    required double rate,
  }) async {
    final res =
        await ApiClient.instance.postJson(ApiConfig.api("/admin/commission"), {
      "kind": kind,
      "state": state,
      "category": category,
      "rate": rate,
    });
    return res is Map && res["ok"] == true;
  }

  Future<bool> disableRule(int id) async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api("/admin/commission/$id/disable"), {});
    return res is Map && res["ok"] == true;
  }
}
