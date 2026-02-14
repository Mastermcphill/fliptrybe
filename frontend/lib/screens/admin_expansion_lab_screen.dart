import 'package:flutter/material.dart';

import '../services/omega_intelligence_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminExpansionLabScreen extends StatefulWidget {
  const AdminExpansionLabScreen({
    super.key,
    this.service,
    this.initialResult,
  });

  final OmegaIntelligenceService? service;
  final Map<String, dynamic>? initialResult;

  @override
  State<AdminExpansionLabScreen> createState() => _AdminExpansionLabScreenState();
}

class _AdminExpansionLabScreenState extends State<AdminExpansionLabScreen> {
  late final OmegaIntelligenceService _svc;
  final _cityCtrl = TextEditingController(text: 'Lagos');
  final _listingsCtrl = TextEditingController(text: '80');
  final _dailyGmvCtrl = TextEditingController(text: '75000000');
  final _aovCtrl = TextEditingController(text: '1200000');
  final _marketingCtrl = TextEditingController(text: '500000000');
  final _commissionCtrl = TextEditingController(text: '500');
  final _opexCtrl = TextEditingController(text: '1800000');

  bool _loading = false;
  String? _error;
  Map<String, dynamic> _result = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? OmegaIntelligenceService();
    if (widget.initialResult != null) {
      _result = Map<String, dynamic>.from(widget.initialResult!);
    }
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _listingsCtrl.dispose();
    _dailyGmvCtrl.dispose();
    _aovCtrl.dispose();
    _marketingCtrl.dispose();
    _commissionCtrl.dispose();
    _opexCtrl.dispose();
    super.dispose();
  }

  int _asInt(String value, int fallback) => int.tryParse(value.trim()) ?? fallback;

  Future<void> _simulate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _svc.expansionSimulate(
        targetCity: _cityCtrl.text.trim(),
        assumedListings: _asInt(_listingsCtrl.text, 0),
        assumedDailyGmvMinor: _asInt(_dailyGmvCtrl.text, 0),
        averageOrderValueMinor: _asInt(_aovCtrl.text, 1),
        marketingBudgetMinor: _asInt(_marketingCtrl.text, 0),
        estimatedCommissionBps: _asInt(_commissionCtrl.text, 500),
        operatingCostDailyMinor: _asInt(_opexCtrl.text, 0),
      );
      if (!mounted) return;
      setState(() => _result = res);
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

  @override
  Widget build(BuildContext context) {
    final unit = (_result['unit_economics'] is Map)
        ? Map<String, dynamic>.from(_result['unit_economics'] as Map)
        : const <String, dynamic>{};
    return FTScaffold(
      title: 'Expansion Lab',
      child: FTLoadStateLayout(
        loading: false,
        error: _error,
        onRetry: _simulate,
        loadingState: const SizedBox.shrink(),
        empty: false,
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            const FTCard(
              child: FTResponsiveTitleAction(
                title: 'Expansion simulation',
                subtitle:
                    'Read-only scenario planning for city rollout. No real balances are changed.',
              ),
            ),
            const SizedBox(height: 10),
            FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FTResponsiveTitleAction(
                    title: 'Inputs',
                    subtitle: 'Provide deterministic assumptions for 6-month model.',
                  ),
                  const SizedBox(height: 8),
                  FTInput(controller: _cityCtrl, label: 'Target city'),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _listingsCtrl,
                    label: 'Assumed listings',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _dailyGmvCtrl,
                    label: 'Assumed daily GMV (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _aovCtrl,
                    label: 'Average order value (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _marketingCtrl,
                    label: 'Marketing budget (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _commissionCtrl,
                    label: 'Estimated commission (bps)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _opexCtrl,
                    label: 'Operating cost daily (minor)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  FTButton(
                    icon: Icons.science_outlined,
                    label: _loading ? 'Running...' : 'Run expansion simulation',
                    onPressed: _loading ? null : _simulate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_result.isNotEmpty)
              FTCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FTResponsiveTitleAction(
                      title: 'Outputs',
                      subtitle: 'Projected economics over 6 months.',
                    ),
                    const SizedBox(height: 8),
                    FTMetricTile(
                      label: 'Projected 6-month GMV',
                      value: formatNaira(
                        (( _result['projected_6_month_gmv_minor'] as num?)?.toInt() ?? 0) / 100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FTMetricTile(
                      label: 'Projected commission revenue',
                      value: formatNaira(
                        (( _result['projected_commission_revenue_minor'] as num?)?.toInt() ?? 0) / 100,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FTMetricTile(
                      label: 'CAC break-even days',
                      value: '${_result['cac_break_even_days'] ?? 'N/A'}',
                      subtitle:
                          'Confidence: ${(_result['confidence_score'] ?? 'low').toString().toUpperCase()}',
                    ),
                    const SizedBox(height: 8),
                    FTMetricTile(
                      label: 'ROI projection',
                      value:
                          '${((_result['roi_projection_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}%',
                      subtitle: (_result['liquidity_stress_indicator'] == true)
                          ? 'Liquidity stress indicator: ELEVATED'
                          : 'Liquidity stress indicator: STABLE',
                    ),
                    const SizedBox(height: 8),
                    FTMetricTile(
                      label: 'Estimated CAC',
                      value: formatNaira(
                        ((unit['estimated_cac_minor'] as num?)?.toInt() ?? 0) / 100,
                      ),
                      subtitle: 'LTV estimate: ${formatNaira(((unit['ltv_estimation_minor'] as num?)?.toInt() ?? 0) / 100)}',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
