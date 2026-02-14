import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/omega_intelligence_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminElasticityDashboardScreen extends StatefulWidget {
  const AdminElasticityDashboardScreen({
    super.key,
    this.service,
    this.autoLoad = true,
    this.initialData,
  });

  final OmegaIntelligenceService? service;
  final bool autoLoad;
  final Map<String, dynamic>? initialData;

  @override
  State<AdminElasticityDashboardScreen> createState() =>
      _AdminElasticityDashboardScreenState();
}

class _AdminElasticityDashboardScreenState
    extends State<AdminElasticityDashboardScreen> {
  late final OmegaIntelligenceService _svc;
  final _cityCtrl = TextEditingController(text: 'all');
  String _category = 'declutter';
  String _sellerType = 'all';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? OmegaIntelligenceService();
    if (widget.initialData != null) {
      _data = Map<String, dynamic>.from(widget.initialData!);
      _loading = false;
      return;
    }
    if (widget.autoLoad) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _svc.elasticitySegment(
        category: _category,
        city: _cityCtrl.text.trim().isEmpty ? 'all' : _cityCtrl.text.trim(),
        sellerType: _sellerType,
      );
      if (!mounted) return;
      setState(() => _data = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = UIFeedback.mapDioErrorToMessage(e));
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _curveChart() {
    final pointsRaw = (_data['conversion_curve'] is List)
        ? (_data['conversion_curve'] as List)
        : const [];
    if (pointsRaw.isEmpty) {
      return const FTEmptyState(
        icon: Icons.show_chart_outlined,
        title: 'No curve data',
        subtitle: 'Run elasticity for a segment with more activity.',
      );
    }
    final points = <FlSpot>[];
    for (final row in pointsRaw) {
      if (row is! Map) continue;
      final x = (row['price_mid_minor'] as num?)?.toDouble() ?? 0;
      final y = (row['conversion_proxy'] as num?)?.toDouble() ?? 0;
      points.add(FlSpot(x, y));
    }
    if (points.length < 2) {
      return const FTEmptyState(
        icon: Icons.show_chart_outlined,
        title: 'Not enough points',
        subtitle: 'At least two price buckets are required.',
      );
    }
    final minY = points.fold<double>(points.first.y, (a, b) => b.y < a ? b.y : a);
    final maxY = points.fold<double>(points.first.y, (a, b) => b.y > a ? b.y : a);
    final maxX = points.fold<double>(points.first.x, (a, b) => b.x > a ? b.x : a);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX <= 0 ? 1 : maxX,
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
              spots: points,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final coef = (_data['elasticity_coefficient'] as num?)?.toDouble() ?? 0.0;
    final sensitivity = (_data['price_sensitivity'] ?? 'low').toString();
    final shift = (_data['recommended_price_shift_pct'] as num?)?.toDouble() ?? 0.0;
    final confidence = (_data['confidence'] ?? 'low').toString();
    final sampleSize = (_data['sample_size'] as num?)?.toInt() ?? 0;

    return FTScaffold(
      title: 'Elasticity Dashboard',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        loadingState: const FTSkeletonList(
          itemCount: 4,
          itemBuilder: _skeletonCard,
        ),
        empty: false,
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FTResponsiveTitleAction(
                    title: 'Segment',
                    subtitle:
                        'Choose category, city and seller type to recompute elasticity.',
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'declutter',
                        child: Text('Declutter'),
                      ),
                      DropdownMenuItem(
                        value: 'shortlet',
                        child: Text('Shortlet'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _category = v ?? 'declutter'),
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _cityCtrl,
                    label: 'City (all for nationwide)',
                    helper: 'Example: Lagos, Abuja, all',
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _sellerType,
                    decoration: const InputDecoration(
                      labelText: 'Seller type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All')),
                      DropdownMenuItem(value: 'user', child: Text('User')),
                      DropdownMenuItem(
                        value: 'merchant',
                        child: Text('Merchant'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _sellerType = v ?? 'all'),
                  ),
                  const SizedBox(height: 10),
                  FTButton(
                    icon: Icons.auto_graph_outlined,
                    label: 'Compute elasticity',
                    onPressed: _loading ? null : _load,
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
                    title: 'Elasticity Signals',
                    subtitle: 'Deterministic regression-lite from real history.',
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Elasticity coefficient',
                    value: coef.toStringAsFixed(3),
                    subtitle: 'Negative = higher prices reduce conversion.',
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Sensitivity',
                    value: sensitivity.toUpperCase(),
                    subtitle: 'Confidence: ${confidence.toUpperCase()}',
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Recommended price shift',
                    value: '${shift >= 0 ? '+' : ''}${shift.toStringAsFixed(1)}%',
                    subtitle: 'Sample size: $sampleSize transactions',
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
                    title: 'Conversion Curve',
                    subtitle: 'Price midpoint vs conversion proxy per bucket.',
                  ),
                  const SizedBox(height: 10),
                  _curveChart(),
                ],
              ),
            ),
            if (_data['explanation'] is List) ...[
              const SizedBox(height: 10),
              FTCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FTResponsiveTitleAction(
                      title: 'Explainability',
                      subtitle: 'Why this recommendation was produced.',
                    ),
                    const SizedBox(height: 8),
                    ...((_data['explanation'] as List)
                        .map((e) => Text('- ${e.toString()}'))),
                  ],
                ),
              ),
            ],
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
