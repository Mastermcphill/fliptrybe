import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';

class GrowthAnalyticsService {
  Future<Map<String, dynamic>> adminOverview() async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/admin/analytics/overview'),
    );
    return _toMap(data);
  }

  Future<Map<String, dynamic>> adminRevenueBreakdown() async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/admin/analytics/revenue-breakdown'),
    );
    return _toMap(data);
  }

  Future<Map<String, dynamic>> adminProjection({int months = 6}) async {
    final uri = Uri.parse(ApiConfig.api('/admin/analytics/projection')).replace(
      queryParameters: {'months': '$months'},
    );
    final data = await ApiClient.instance.getJson(uri.toString());
    return _toMap(data);
  }

  Future<Map<String, dynamic>> adminEconomicsHealth() async {
    final data = await ApiClient.instance.getJson(
      ApiConfig.api('/admin/economics/health'),
    );
    return _toMap(data);
  }

  Future<String> adminExportCsvRaw() async {
    final res = await ApiClient.instance.dio.get<String>(
      ApiConfig.api('/admin/analytics/export-csv'),
      options: Options(responseType: ResponseType.plain),
    );
    return (res.data ?? '').toString();
  }

  Future<Map<String, dynamic>> merchantAnalytics() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/merchant/analytics'));
    return _toMap(data);
  }

  Future<Map<String, dynamic>> buyerAnalytics() async {
    final data =
        await ApiClient.instance.getJson(ApiConfig.api('/buyer/analytics'));
    return _toMap(data);
  }

  Future<Map<String, dynamic>> investorAnalytics({int? cacMinor}) async {
    final query = <String, String>{};
    if (cacMinor != null) query['cac_minor'] = '$cacMinor';
    final uri = Uri.parse(ApiConfig.api('/investor/analytics'))
        .replace(queryParameters: query.isEmpty ? null : query);
    final data = await ApiClient.instance.getJson(uri.toString());
    return _toMap(data);
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
