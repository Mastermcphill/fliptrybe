import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_config.dart';

class ReceiptService {
  ReceiptService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<List<dynamic>> listReceipts() async {
    try {
      final res = await _client.dio.get(ApiConfig.api('/receipts'));
      final data = res.data;
      if (data is Map && data['items'] is List) return data['items'] as List;
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<dynamic>> getByReference(String reference) async {
    final rows = await listReceipts();
    return rows.where((r) {
      if (r is! Map) return false;
      final m = Map<String, dynamic>.from(r as Map);
      return (m['reference'] ?? '').toString() == reference;
    }).toList();
  }

  Future<String> getPdfUrl(int receiptId) async {
    return ApiConfig.api('/receipts/$receiptId/pdf');
  }
}
