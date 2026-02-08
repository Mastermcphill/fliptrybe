import 'api_client.dart';
import 'api_config.dart';

class WalletService {
  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry('$k', v));
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>?> getWallet() async {
    try {
      final data = await ApiClient.instance.getJson(ApiConfig.api('/wallet'));
      if (data is Map && data['wallet'] is Map) return Map<String, dynamic>.from(data['wallet'] as Map);
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> ledger() async {
    try {
      final data = await ApiClient.instance.getJson(ApiConfig.api('/wallet/ledger'));
      return data is List ? data : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> getTxns() async {
    return ledger();
  }

  Future<bool> demoTopup(double amount) async {
    try {
      final data = await ApiClient.instance.postJson(ApiConfig.api('/wallet/topup-demo'), {'amount': amount});
      return data is Map && data['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<dynamic>> payouts() async {
    try {
      final data = await ApiClient.instance.getJson(ApiConfig.api('/wallet/payouts'));
      return data is List ? data : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> requestPayout({
    required double amount,
    required String bankName,
    required String accountNumber,
    required String accountName,
  }) async {
    try {
      final res = await ApiClient.instance.dio.post(ApiConfig.api('/wallet/payouts'), data: {
        'amount': amount,
        'bank_name': bankName,
        'account_number': accountNumber,
        'account_name': accountName,
      });
      final data = _asMap(res.data);
      final status = res.statusCode ?? 0;
      final ok = status >= 200 && status < 300 && data['ok'] != false;
      data['ok'] = ok;
      data['status'] = status;
      return data;
    } catch (_) {
      return {'ok': false, 'message': 'Request failed'};
    }
  }
}
