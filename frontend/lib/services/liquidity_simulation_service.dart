import 'package:dio/dio.dart';

import 'api_client.dart';
import 'api_config.dart';

class LiquiditySimulationService {
  Future<Map<String, dynamic>> baseline() async {
    final raw =
        await ApiClient.instance.getJson(ApiConfig.api('/admin/simulation/baseline'));
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> run({
    required int timeHorizonDays,
    required int assumedDailyGmvMinor,
    required double assumedOrderCountDaily,
    required double withdrawalRatePct,
    required int payoutDelayDays,
    required double chargebackRatePct,
    required int operatingCostDailyMinor,
    required int commissionBps,
    required String scenario,
  }) async {
    final raw = await ApiClient.instance.postJson(
      ApiConfig.api('/admin/simulation/liquidity'),
      <String, dynamic>{
        'time_horizon_days': timeHorizonDays,
        'assumed_daily_gmv_minor': assumedDailyGmvMinor,
        'assumed_order_count_daily': assumedOrderCountDaily,
        'withdrawal_rate_pct': withdrawalRatePct,
        'payout_delay_days': payoutDelayDays,
        'chargeback_rate_pct': chargebackRatePct,
        'operating_cost_daily_minor': operatingCostDailyMinor,
        'commission_bps': commissionBps,
        'scenario': scenario,
      },
    );
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{'ok': false};
  }

  Future<String> exportCsvRaw({
    required int timeHorizonDays,
    required int assumedDailyGmvMinor,
    required double assumedOrderCountDaily,
    required double withdrawalRatePct,
    required int payoutDelayDays,
    required double chargebackRatePct,
    required int operatingCostDailyMinor,
    required int commissionBps,
    required String scenario,
  }) async {
    final uri = Uri.parse(ApiConfig.api('/admin/simulation/export-csv')).replace(
      queryParameters: <String, String>{
        'time_horizon_days': '$timeHorizonDays',
        'assumed_daily_gmv_minor': '$assumedDailyGmvMinor',
        'assumed_order_count_daily': '$assumedOrderCountDaily',
        'withdrawal_rate_pct': '$withdrawalRatePct',
        'payout_delay_days': '$payoutDelayDays',
        'chargeback_rate_pct': '$chargebackRatePct',
        'operating_cost_daily_minor': '$operatingCostDailyMinor',
        'commission_bps': '$commissionBps',
        'scenario': scenario,
      },
    );
    final res = await ApiClient.instance.dio.get<String>(
      uri.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    return (res.data ?? '').toString();
  }
}
