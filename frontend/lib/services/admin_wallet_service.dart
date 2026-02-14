import 'api_client.dart';
import 'api_config.dart';

class AdminWalletService {
  Future<List<dynamic>> listPayouts({String status = ""}) async {
    final uri = Uri.parse(ApiConfig.api("/wallet/admin/payouts")).replace(
        queryParameters:
            status.trim().isEmpty ? null : {"status": status.trim()});
    final data = await ApiClient.instance.getJson(uri.toString());
    return data is List ? data : <dynamic>[];
  }

  Future<bool> approve(int payoutId) async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api("/wallet/payouts/$payoutId/admin/approve"), {});
    return res is Map && res["ok"] == true;
  }

  Future<bool> reject(int payoutId) async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api("/wallet/payouts/$payoutId/admin/reject"), {});
    return res is Map && res["ok"] == true;
  }

  Future<bool> process(int payoutId) async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api('/wallet/payouts/$payoutId/admin/process'), {});
    return res is Map && res['ok'] == true;
  }

  Future<bool> pay(int payoutId) async {
    final res = await ApiClient.instance
        .postJson(ApiConfig.api("/wallet/payouts/$payoutId/admin/pay"), {});
    return res is Map && res["ok"] == true;
  }

  Future<bool> markPaid(int payoutId) async {
    final res = await ApiClient.instance.postJson(
        ApiConfig.api("/wallet/payouts/$payoutId/admin/mark-paid"), {});
    return res is Map && res["ok"] == true;
  }
}
