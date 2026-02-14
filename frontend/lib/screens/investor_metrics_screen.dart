import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/growth_analytics_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/csv_download.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class InvestorMetricsScreen extends StatefulWidget {
  const InvestorMetricsScreen({super.key});

  @override
  State<InvestorMetricsScreen> createState() => _InvestorMetricsScreenState();
}

class _InvestorMetricsScreenState extends State<InvestorMetricsScreen> {
  final GrowthAnalyticsService _service = GrowthAnalyticsService();
  final TextEditingController _cacController = TextEditingController();

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  Map<String, dynamic> _investor = const <String, dynamic>{};
  Map<String, dynamic> _overview = const <String, dynamic>{};
  Map<String, dynamic> _breakdown = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cacController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cacMinor = int.tryParse(_cacController.text.trim());
      final values = await Future.wait<dynamic>([
        _service.investorAnalytics(cacMinor: cacMinor),
        _service.adminOverview(),
        _service.adminRevenueBreakdown(),
      ]);
      if (!mounted) return;
      setState(() {
        _investor = Map<String, dynamic>.from(values[0] as Map);
        _overview = Map<String, dynamic>.from(values[1] as Map);
        _breakdown = Map<String, dynamic>.from(values[2] as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UIFeedback.mapDioErrorToMessage(e);
        _loading = false;
      });
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? 0}') ?? 0;
  }

  List<Map<String, dynamic>> _trendRows() {
    final rows = _investor['gmv_trend'];
    if (rows is! List) return const <Map<String, dynamic>>[];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Widget _trendChart() {
    final rows = _trendRows();
    if (rows.length < 2) {
      return const FTEmptyState(
        icon: Icons.trending_up,
        title: 'Trend pending',
        subtitle: 'More monthly data is required for a clean trend line.',
      );
    }
    final spots = <FlSpot>[];
    final labels = <String>[];
    for (var i = 0; i < rows.length; i++) {
      spots.add(FlSpot(i.toDouble(), _asInt(rows[i]['gmv_minor']).toDouble()));
      labels.add((rows[i]['month'] ?? '').toString());
    }
    final maxY =
        spots.fold<double>(0, (prev, row) => row.y > prev ? row.y : prev) * 1.1;

    return SizedBox(
      height: 230,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY <= 0 ? 1 : maxY / 4,
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: maxY <= 0 ? 1 : maxY / 4,
                getTitlesWidget: (value, _) => Text(
                  formatNaira(value / 100, decimals: 0),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: rows.length > 6 ? 2 : 1,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[idx],
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await _service.adminExportCsvRaw();
      final ok = await downloadCsvFile(
        fileName: 'fliptrybe-analytics.csv',
        content: csv,
      );
      if (ok) {
        if (!mounted) return;
        UIFeedback.showSuccessSnack(context, 'CSV export downloaded.');
      } else {
        await Clipboard.setData(ClipboardData(text: csv));
        if (!mounted) return;
        UIFeedback.showSuccessSnack(
          context,
          'CSV copied to clipboard (download not supported on this platform).',
        );
      }
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalGmvMinor = _asInt(_overview['total_gmv_minor']);
    final commissionMinor = _asInt(_overview['total_commission_minor']);
    final activeUsers = _asInt(_investor['active_users_last_30_days']);
    final unitRaw = _investor['unit_economics'];
    final unit = unitRaw is Map
        ? Map<String, dynamic>.from(unitRaw)
        : const <String, dynamic>{};
    final avgOrderMinor = _asInt(unit['avg_order_value_minor']);
    final avgCommissionMinor = _asInt(unit['avg_commission_per_order_minor']);
    final cacMinor = _asInt(unit['cac_minor']);
    final ltvMinor = _asInt(unit['ltv_estimate_minor']);
    final declutterGmv = _asInt(_breakdown['declutter_gmv']);
    final shortletGmv = _asInt(_breakdown['shortlet_gmv']);

    return FTScaffold(
      title: 'Investor Dashboard',
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'Export CSV',
          onPressed: _exporting ? null : _exportCsv,
          icon: const Icon(Icons.download_outlined),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: false,
        loadingState: FTSkeletonList(
          itemCount: 5,
          itemBuilder: (context, index) => const FTSkeletonCard(height: 100),
        ),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            FTSection(
              title: 'Headline Metrics',
              subtitle: 'GMV and commission values are backend-derived.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FTMetricTile(
                          label: 'GMV',
                          value: formatNaira(totalGmvMinor / 100),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FTMetricTile(
                          label: 'Commission Revenue',
                          value: formatNaira(commissionMinor / 100),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: FTMetricTile(
                          label: 'Declutter GMV',
                          value: formatNaira(declutterGmv / 100),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FTMetricTile(
                          label: 'Shortlet GMV',
                          value: formatNaira(shortletGmv / 100),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Unit Economics',
              subtitle: 'Input CAC to inspect LTV estimate.',
              child: Column(
                children: [
                  FTInput(
                    controller: _cacController,
                    keyboardType: TextInputType.number,
                    hint: 'CAC (minor units, optional)',
                    prefixIcon: Icons.tune,
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Recompute with CAC',
                    icon: Icons.calculate_outlined,
                    variant: FTButtonVariant.ghost,
                    onPressed: _load,
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Average Order Value',
                    value: formatNaira(avgOrderMinor / 100),
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Average Commission / Order',
                    value: formatNaira(avgCommissionMinor / 100),
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'CAC',
                    value: formatNaira(cacMinor / 100),
                    subtitle: 'LTV Estimate: ${formatNaira(ltvMinor / 100)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'GMV Trend',
              subtitle: 'Monthly trend from paid order + booking history.',
              child: _trendChart(),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Operational Signal',
              subtitle: 'Engagement and distribution quality.',
              child: FTMetricTile(
                label: 'Active users (30d)',
                value: '$activeUsers',
                icon: Icons.people_outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
