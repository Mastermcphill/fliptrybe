import 'package:flutter/material.dart';

import '../services/omega_intelligence_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminMarketBalancerScreen extends StatefulWidget {
  const AdminMarketBalancerScreen({super.key});

  @override
  State<AdminMarketBalancerScreen> createState() =>
      _AdminMarketBalancerScreenState();
}

class _AdminMarketBalancerScreenState extends State<AdminMarketBalancerScreen> {
  final _svc = OmegaIntelligenceService();
  final _horizonCtrl = TextEditingController(text: '90');
  final _shiftCityCtrl = TextEditingController();
  final _shiftBpsCtrl = TextEditingController(text: '0');
  final _promoCityCtrl = TextEditingController();
  final _promoBpsCtrl = TextEditingController(text: '0');
  final _payoutDelayCtrl = TextEditingController(text: '0');

  bool _loading = true;
  bool _running = false;
  String? _error;
  Map<String, dynamic> _result = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _simulate();
  }

  @override
  void dispose() {
    _horizonCtrl.dispose();
    _shiftCityCtrl.dispose();
    _shiftBpsCtrl.dispose();
    _promoCityCtrl.dispose();
    _promoBpsCtrl.dispose();
    _payoutDelayCtrl.dispose();
    super.dispose();
  }

  int _asInt(String value, int fallback) => int.tryParse(value.trim()) ?? fallback;

  Future<void> _simulate() async {
    if (_running) return;
    setState(() {
      _running = true;
      _loading = true;
      _error = null;
    });
    try {
      final res = await _svc.crossMarketSimulate(
        timeHorizonDays: _asInt(_horizonCtrl.text, 90),
        commissionShiftCity: _shiftCityCtrl.text.trim(),
        commissionShiftBps: _asInt(_shiftBpsCtrl.text, 0),
        promoCity: _promoCityCtrl.text.trim(),
        promoDiscountBps: _asInt(_promoBpsCtrl.text, 0),
        payoutDelayAdjustmentDays: _asInt(_payoutDelayCtrl.text, 0),
      );
      if (!mounted) return;
      setState(() => _result = res);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = UIFeedback.mapDioErrorToMessage(e));
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = (_result['cities'] is List)
        ? (_result['cities'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final summary = (_result['summary'] is Map)
        ? Map<String, dynamic>.from(_result['summary'] as Map)
        : const <String, dynamic>{};
    final stressed = (summary['stressed_cities_after'] is List)
        ? List<dynamic>.from(summary['stressed_cities_after'] as List)
        : const <dynamic>[];

    return FTScaffold(
      title: 'Market Balancer',
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _simulate,
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
                subtitle:
                    'No automatic balancing is applied. Use this for read-only planning.',
              ),
            ),
            const SizedBox(height: 10),
            FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FTResponsiveTitleAction(
                    title: 'Scenario Inputs',
                    subtitle: 'Adjust fee shift, promo and payout timing.',
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _horizonCtrl,
                    label: 'Time horizon (days)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _shiftCityCtrl,
                    label: 'Commission shift city',
                    helper: 'Example: Lagos',
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _shiftBpsCtrl,
                    label: 'Commission shift (bps)',
                    helper: 'Positive increases, negative decreases.',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _promoCityCtrl,
                    label: 'Promo city',
                    helper: 'Optional city for discount simulation.',
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _promoBpsCtrl,
                    label: 'Promo discount (bps)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 8),
                  FTInput(
                    controller: _payoutDelayCtrl,
                    label: 'Payout delay adjustment (days)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  FTButton(
                    icon: Icons.science_outlined,
                    label: _running ? 'Running...' : 'Run simulation',
                    onPressed: _running ? null : _simulate,
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
                    title: 'Summary',
                    subtitle: 'Cross-market liquidity risk indicators.',
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Projected total float',
                    value: formatNaira(
                      ((summary['projected_total_float_minor'] as num?)?.toInt() ?? 0) /
                          100,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FTMetricTile(
                    label: 'Cross-market risk',
                    value: (summary['cross_market_liquidity_risk'] == true)
                        ? 'ELEVATED'
                        : 'STABLE',
                    subtitle: stressed.isEmpty
                        ? 'No stressed cities in projection.'
                        : 'Stressed cities: ${stressed.join(', ')}',
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
                    title: 'City Comparison',
                    subtitle: 'Projected float by city after adjustments.',
                  ),
                  const SizedBox(height: 8),
                  if (cities.isEmpty)
                    const FTEmptyState(
                      icon: Icons.location_city_outlined,
                      title: 'No city metrics',
                      subtitle: 'Run simulation to populate city rows.',
                    )
                  else
                    ...cities.map((row) {
                      final city = (row['city'] ?? 'Unknown').toString();
                      final bps =
                          (row['effective_commission_bps'] as num?)?.toInt() ?? 0;
                      final floatMinor =
                          (row['projected_float_minor'] as num?)?.toInt() ?? 0;
                      final ratio = (row['projected_float_ratio'] as num?)
                              ?.toDouble() ??
                          0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FTTile(
                          leading: const Icon(Icons.location_city_outlined),
                          title: Text(city),
                          subtitle: Text(
                            'Bps: $bps | Float: ${formatNaira(floatMinor / 100)} | Ratio: ${(ratio * 100).toStringAsFixed(2)}%',
                          ),
                        ),
                      );
                    }),
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
