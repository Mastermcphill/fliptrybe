import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/growth_analytics_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminGrowthAnalyticsScreen extends StatefulWidget {
  const AdminGrowthAnalyticsScreen({super.key});

  @override
  State<AdminGrowthAnalyticsScreen> createState() =>
      _AdminGrowthAnalyticsScreenState();
}

class _AdminGrowthAnalyticsScreenState
    extends State<AdminGrowthAnalyticsScreen> {
  final GrowthAnalyticsService _service = GrowthAnalyticsService();

  static const Map<String, int> _rangeMonths = {
    'Last 30 days': 1,
    'Last 90 days': 3,
    'Last 1 year': 12,
  };

  bool _loading = true;
  String? _error;
  String _rangeLabel = 'Last 90 days';

  Map<String, dynamic> _overview = const <String, dynamic>{};
  Map<String, dynamic> _breakdown = const <String, dynamic>{};
  Map<String, dynamic> _projection = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _selectedMonths => _rangeMonths[_rangeLabel] ?? 3;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<dynamic>([
        _service.adminOverview(),
        _service.adminRevenueBreakdown(),
        _service.adminProjection(months: _selectedMonths),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = Map<String, dynamic>.from(values[0] as Map);
        _breakdown = Map<String, dynamic>.from(values[1] as Map);
        _projection = Map<String, dynamic>.from(values[2] as Map);
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

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? 0}') ?? 0;
  }

  List<Map<String, dynamic>> _lineSeriesRows() {
    final historyRaw = _projection['history'];
    final projectionRaw = _projection['projections'];
    final history = historyRaw is List
        ? historyRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final proj = projectionRaw is List
        ? projectionRaw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];

    final series = <Map<String, dynamic>>[];
    for (final row in history) {
      series.add(<String, dynamic>{
        'month': (row['month'] ?? '').toString(),
        'gmv_minor': _asInt(row['gmv_minor']),
        'is_projection': false,
      });
    }
    for (final row in proj) {
      series.add(<String, dynamic>{
        'month': (row['month'] ?? '').toString(),
        'gmv_minor': _asInt(row['projected_gmv_minor']),
        'is_projection': true,
      });
    }
    if (series.length > 12) {
      return series.sublist(series.length - 12);
    }
    return series;
  }

  Widget _lineChart() {
    final rows = _lineSeriesRows();
    if (rows.length < 2) {
      return const FTEmptyState(
        icon: Icons.show_chart,
        title: 'Not enough data',
        subtitle: 'Growth trend will appear once more periods are available.',
      );
    }
    final spots = <FlSpot>[];
    for (var i = 0; i < rows.length; i++) {
      spots.add(FlSpot(i.toDouble(), _asInt(rows[i]['gmv_minor']).toDouble()));
    }
    final labels = rows
        .map((row) => (row['month'] ?? '').toString())
        .toList(growable: false);
    final maxY =
        spots.fold<double>(0, (prev, row) => row.y > prev ? row.y : prev) * 1.1;

    return SizedBox(
      height: 240,
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
                getTitlesWidget: (value, meta) {
                  return Text(
                    formatNaira(value / 100, decimals: 0),
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: rows.length > 6 ? 2 : 1,
                getTitlesWidget: (value, meta) {
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

  Widget _revenuePie() {
    final commissions = _breakdown['commissions_by_type'];
    final map = commissions is Map
        ? Map<String, dynamic>.from(commissions)
        : <String, dynamic>{};
    final values = <MapEntry<String, int>>[];
    for (final entry in map.entries) {
      values.add(MapEntry(entry.key, _asInt(entry.value)));
    }
    final total = values.fold<int>(0, (sum, row) => sum + row.value);
    if (total <= 0) {
      return const FTEmptyState(
        icon: Icons.pie_chart_outline,
        title: 'No revenue split yet',
        subtitle: 'Commission breakdown appears after revenue events.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final palette = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
    ];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: List<PieChartSectionData>.generate(values.length, (i) {
                final value = values[i].value;
                final pct = total <= 0 ? 0 : (value / total) * 100;
                return PieChartSectionData(
                  color: palette[i % palette.length],
                  value: value.toDouble(),
                  radius: 52,
                  title: '${pct.toStringAsFixed(0)}%',
                  titleStyle: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onPrimary),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<Widget>.generate(values.length, (index) {
            final entry = values[index];
            return FTBadge(
              text: '${entry.key}: ${formatNaira(entry.value / 100)}',
              backgroundColor:
                  palette[index % palette.length].withValues(alpha: 0.14),
              textColor: Theme.of(context).colorScheme.onSurface,
            );
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalGmvMinor = _asInt(_overview['total_gmv_minor']);
    final totalCommissionMinor = _asInt(_overview['total_commission_minor']);
    final activeUsers = _asInt(_overview['active_users_last_30_days']);
    final totalUsers = _asInt(_overview['total_users']);
    final merchantGmv = _asInt(_breakdown['merchant_gmv']);
    final growthRate = _asDouble(_overview['monthly_growth_rate']);

    return AdminScaffold(
      title: 'Growth Analytics',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: false,
        loadingState: FTSkeletonList(
          itemCount: 6,
          itemBuilder: (context, index) => const FTSkeletonCard(height: 96),
        ),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            FTSection(
              title: 'Date range',
              subtitle: 'Filter trend and projection horizon.',
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _rangeLabel,
                      items: _rangeMonths.keys
                          .map(
                            (label) => DropdownMenuItem<String>(
                              value: label,
                              child: Text(label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) async {
                        if (value == null || value == _rangeLabel) return;
                        setState(() => _rangeLabel = value);
                        await _load();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FTMetricTile(
                    label: 'GMV',
                    value: formatNaira(totalGmvMinor / 100),
                    subtitle: 'All-time',
                    icon: Icons.payments_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTMetricTile(
                    label: 'Commission Revenue',
                    value: formatNaira(totalCommissionMinor / 100),
                    subtitle: 'Ledger-derived',
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
                    label: 'Active Users (30d)',
                    value: '$activeUsers',
                    subtitle: 'Traffic quality signal',
                    icon: Icons.people_alt_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTMetricTile(
                    label: 'Total Users',
                    value: '$totalUsers',
                    subtitle: 'Growth rate ${growthRate.toStringAsFixed(2)}%',
                    icon: Icons.group_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Merchant Earnings Overview',
              subtitle: 'Merchant GMV derived from settled order snapshots.',
              child: FTMetricTile(
                label: 'Merchant GMV',
                value: formatNaira(merchantGmv / 100),
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Monthly GMV Trend',
              subtitle: 'Historical + projected trajectory.',
              child: _lineChart(),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Revenue Breakdown',
              subtitle: 'Commission composition by type.',
              child: _revenuePie(),
            ),
          ],
        ),
      ),
    );
  }
}
