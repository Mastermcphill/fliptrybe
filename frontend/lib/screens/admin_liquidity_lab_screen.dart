import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/liquidity_simulation_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/csv_download.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminLiquidityLabScreen extends StatefulWidget {
  const AdminLiquidityLabScreen({super.key});

  @override
  State<AdminLiquidityLabScreen> createState() => _AdminLiquidityLabScreenState();
}

class _AdminLiquidityLabScreenState extends State<AdminLiquidityLabScreen> {
  final _svc = LiquiditySimulationService();
  final _gmvCtrl = TextEditingController();
  final _ordersCtrl = TextEditingController();
  final _withdrawalCtrl = TextEditingController();
  final _delayCtrl = TextEditingController(text: '3');
  final _chargebackCtrl = TextEditingController(text: '1.5');
  final _opexCtrl = TextEditingController(text: '0');
  final _commissionCtrl = TextEditingController(text: '500');
  final _horizonCtrl = TextEditingController(text: '90');

  bool _loading = true;
  bool _running = false;
  bool _exporting = false;
  String? _error;
  String _scenario = 'base';
  Map<String, dynamic> _result = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _loadBaseline();
  }

  @override
  void dispose() {
    _gmvCtrl.dispose();
    _ordersCtrl.dispose();
    _withdrawalCtrl.dispose();
    _delayCtrl.dispose();
    _chargebackCtrl.dispose();
    _opexCtrl.dispose();
    _commissionCtrl.dispose();
    _horizonCtrl.dispose();
    super.dispose();
  }

  int _asInt(String value, int fallback) => int.tryParse(value.trim()) ?? fallback;
  double _asDouble(String value, double fallback) =>
      double.tryParse(value.trim()) ?? fallback;

  Future<void> _loadBaseline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = await _svc.baseline();
      if (!mounted) return;
      setState(() {
        _gmvCtrl.text = '${base['avg_daily_gmv_minor'] ?? 0}';
        _ordersCtrl.text = '${base['avg_daily_orders'] ?? 0}';
        _withdrawalCtrl.text =
            '${((base['withdrawal_ratio'] ?? 0.0) as num).toDouble() * 100}';
      });
      await _runSimulation();
    } catch (e) {
      if (mounted) {
        setState(() => _error = UIFeedback.mapDioErrorToMessage(e));
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _runSimulation() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final res = await _svc.run(
        timeHorizonDays: _asInt(_horizonCtrl.text, 90),
        assumedDailyGmvMinor: _asInt(_gmvCtrl.text, 0),
        assumedOrderCountDaily: _asDouble(_ordersCtrl.text, 0),
        withdrawalRatePct: _asDouble(_withdrawalCtrl.text, 0),
        payoutDelayDays: _asInt(_delayCtrl.text, 3),
        chargebackRatePct: _asDouble(_chargebackCtrl.text, 1.5),
        operatingCostDailyMinor: _asInt(_opexCtrl.text, 0),
        commissionBps: _asInt(_commissionCtrl.text, 500),
        scenario: _scenario,
      );
      if (!mounted) return;
      setState(() => _result = res);
    } catch (e) {
      if (mounted) {
        setState(() => _error = UIFeedback.mapDioErrorToMessage(e));
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  Future<void> _exportScenarioCsv() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await _svc.exportCsvRaw(
        timeHorizonDays: _asInt(_horizonCtrl.text, 90),
        assumedDailyGmvMinor: _asInt(_gmvCtrl.text, 0),
        assumedOrderCountDaily: _asDouble(_ordersCtrl.text, 0),
        withdrawalRatePct: _asDouble(_withdrawalCtrl.text, 0),
        payoutDelayDays: _asInt(_delayCtrl.text, 3),
        chargebackRatePct: _asDouble(_chargebackCtrl.text, 1.5),
        operatingCostDailyMinor: _asInt(_opexCtrl.text, 0),
        commissionBps: _asInt(_commissionCtrl.text, 500),
        scenario: _scenario,
      );
      final downloaded = await downloadCsvFile(
        fileName: 'fliptrybe-liquidity-lab.csv',
        content: csv,
      );
      if (downloaded) {
        if (!mounted) return;
        UIFeedback.showSuccessSnack(context, 'Scenario CSV downloaded.');
      } else {
        await Clipboard.setData(ClipboardData(text: csv));
        if (!mounted) return;
        UIFeedback.showSuccessSnack(
          context,
          'CSV copied to clipboard (download unavailable here).',
        );
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Widget _balanceChart() {
    final series = (_result['series'] is List) ? (_result['series'] as List) : const [];
    if (series.length < 2) {
      return const FTEmptyState(
        icon: Icons.show_chart_outlined,
        title: 'Not enough data',
        subtitle: 'Run a simulation to view the balance trend.',
      );
    }
    final spots = <FlSpot>[];
    for (final row in series) {
      if (row is! Map) continue;
      final day = (row['day'] as num?)?.toDouble() ?? 0;
      final bal = (row['balance_minor'] as num?)?.toDouble() ?? 0;
      spots.add(FlSpot(day, bal));
    }
    final maxY = spots.fold<double>(0, (acc, e) => e.y > acc ? e.y : acc);
    final minY = spots.fold<double>(0, (acc, e) => e.y < acc ? e.y : acc);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: spots.isEmpty ? 1 : spots.last.x,
          minY: minY < 0 ? minY * 1.1 : 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.1,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minBalanceMinor =
        int.tryParse('${_result['min_cash_balance_minor'] ?? 0}') ?? 0;
    final daysToNegative = _result['days_to_negative'];
    final stressPoints = (_result['stress_points'] is List)
        ? (_result['stress_points'] as List)
            .map((e) => e.toString())
            .toList(growable: false)
        : const <String>[];

    return FTScaffold(
      title: 'Liquidity Lab',
      actions: [
        IconButton(
          tooltip: 'Refresh baseline',
          onPressed: _loading ? null : _loadBaseline,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _loadBaseline,
        loadingState: const FTSkeletonList(
          itemCount: 4,
          itemBuilder: _skeletonCard,
        ),
        empty: false,
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            const FTCard(
              child: FTResponsiveTitleAction(
                title: 'Simulation only',
                subtitle: 'Read-only model. It does not affect real balances.',
              ),
            ),
            const SizedBox(height: 10),
            FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FTResponsiveTitleAction(
                    title: 'Scenario Inputs',
                    subtitle: 'Prefilled from last 30-day baseline.',
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _horizonCtrl,
                    label: 'Time horizon (days)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _gmvCtrl,
                    label: 'Assumed daily GMV (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _ordersCtrl,
                    label: 'Assumed daily orders',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _withdrawalCtrl,
                    label: 'Withdrawal rate (%)',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _delayCtrl,
                    label: 'Payout delay (days)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _chargebackCtrl,
                    label: 'Chargeback rate (%)',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _opexCtrl,
                    label: 'Operating cost daily (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _commissionCtrl,
                    label: 'Commission bps',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _scenario,
                    decoration: const InputDecoration(
                      labelText: 'Scenario',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'base', child: Text('Base')),
                      DropdownMenuItem(value: 'optimistic', child: Text('Optimistic')),
                      DropdownMenuItem(value: 'pessimistic', child: Text('Pessimistic')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _scenario = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  FTButton(
                    label: _running ? 'Running...' : 'Run simulation',
                    icon: Icons.science_outlined,
                    onPressed: _running ? null : _runSimulation,
                  ),
                  const SizedBox(height: 8),
                  FTButton(
                    label: _exporting ? 'Exporting...' : 'Export scenario CSV',
                    icon: Icons.download_outlined,
                    variant: FTButtonVariant.ghost,
                    onPressed: _exporting ? null : _exportScenarioCsv,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FTResponsiveTitleAction(
                    title: 'Projected Outputs',
                    subtitle: 'Derived from inputs + baseline wallet state.',
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Projected commission revenue',
                    value: formatNaira(
                      (int.tryParse(
                                    '${_result['projected_commission_revenue_minor'] ?? 0}') ??
                                0) /
                          100,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Projected payouts',
                    value: formatNaira(
                      (int.tryParse('${_result['projected_payouts_minor'] ?? 0}') ??
                              0) /
                          100,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Minimum cash balance',
                    value: formatNaira(minBalanceMinor / 100),
                    subtitle: daysToNegative == null
                        ? 'No negative day in this horizon.'
                        : 'Days to negative: $daysToNegative',
                  ),
                  const SizedBox(height: 8),
                  _balanceChart(),
                  if (stressPoints.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Stress points'),
                    const SizedBox(height: 6),
                    ...stressPoints.take(5).map((line) => Text('• $line')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _skeletonCard(BuildContext context, int _) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: FTSkeletonCard(height: 120),
  );
}
