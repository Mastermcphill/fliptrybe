import 'package:flutter/material.dart';

import '../services/omega_intelligence_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../utils/ft_routes.dart';
import '../utils/ui_feedback.dart';
import 'admin_autopilot_screen.dart';
import 'admin_elasticity_dashboard_screen.dart';
import 'admin_expansion_lab_screen.dart';
import 'admin_fraud_center_screen.dart';
import 'admin_market_balancer_screen.dart';

class AdminOmegaIntelligenceScreen extends StatefulWidget {
  const AdminOmegaIntelligenceScreen({super.key});

  @override
  State<AdminOmegaIntelligenceScreen> createState() =>
      _AdminOmegaIntelligenceScreenState();
}

class _AdminOmegaIntelligenceScreenState
    extends State<AdminOmegaIntelligenceScreen> {
  final _svc = OmegaIntelligenceService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _payload = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _svc.overview();
      if (!mounted) return;
      setState(() => _payload = data);
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

  void _open(Widget child) {
    Navigator.of(context).push(FTRoutes.page(child: child));
  }

  @override
  Widget build(BuildContext context) {
    final panels = (_payload['panels'] is Map)
        ? Map<String, dynamic>.from(_payload['panels'] as Map)
        : const <String, dynamic>{};
    final elasticity = (panels['elasticity_overview'] is Map)
        ? Map<String, dynamic>.from(panels['elasticity_overview'] as Map)
        : const <String, dynamic>{};
    final fraud = (panels['fraud_risk_heatmap'] is Map)
        ? Map<String, dynamic>.from(panels['fraud_risk_heatmap'] as Map)
        : const <String, dynamic>{};
    final liquidity = (panels['liquidity_stress_radar'] is Map)
        ? Map<String, dynamic>.from(panels['liquidity_stress_radar'] as Map)
        : const <String, dynamic>{};
    final opportunities = (panels['expansion_opportunities'] is List)
        ? List<dynamic>.from(panels['expansion_opportunities'] as List)
        : const <dynamic>[];
    final overlay = (panels['autopilot_risk_overlay'] is List)
        ? List<dynamic>.from(panels['autopilot_risk_overlay'] as List)
        : const <dynamic>[];

    return AdminScaffold(
      title: 'Omega Intelligence',
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
          itemCount: 5,
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
                    title: 'Elasticity Overview',
                    subtitle: 'Price sensitivity across declutter and shortlet.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Declutter: ${(elasticity['declutter'] is Map) ? ((elasticity['declutter'] as Map)['coefficient'] ?? 'n/a') : 'n/a'}',
                  ),
                  Text(
                    'Shortlet: ${(elasticity['shortlet'] is Map) ? ((elasticity['shortlet'] as Map)['coefficient'] ?? 'n/a') : 'n/a'}',
                  ),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Open Elasticity Dashboard',
                    icon: Icons.show_chart_outlined,
                    onPressed: () =>
                        _open(const AdminElasticityDashboardScreen()),
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
                    title: 'Fraud Risk Heatmap',
                    subtitle: 'Deterministic fraud score and action queue.',
                  ),
                  const SizedBox(height: 8),
                  Text('Open flags: ${fraud['open_flags'] ?? 0}'),
                  Text('High risk: ${fraud['high_risk_flags'] ?? 0}'),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Open Fraud Center',
                    icon: Icons.shield_outlined,
                    onPressed: () => _open(const AdminFraudCenterScreen()),
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
                    title: 'Liquidity Stress Radar',
                    subtitle: 'Cross-market city stress and surplus signals.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Risk flags: ${((liquidity['risk_flags'] as List?) ?? const []).join(', ')}',
                  ),
                  Text(
                    'Stressed cities: ${((liquidity['stressed_cities'] as List?) ?? const []).join(', ')}',
                  ),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Open Market Balancer',
                    icon: Icons.balance_outlined,
                    onPressed: () => _open(const AdminMarketBalancerScreen()),
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
                    title: 'Expansion Opportunities',
                    subtitle: 'City opportunities derived from live economics.',
                  ),
                  const SizedBox(height: 8),
                  if (opportunities.isEmpty)
                    const Text('No expansion opportunities flagged.')
                  else
                    ...opportunities.take(4).map((row) {
                      if (row is! Map) return const SizedBox.shrink();
                      return Text(
                        '- ${row['city'] ?? 'Unknown'}  (float ratio ${(row['float_ratio'] ?? 0).toString()})',
                      );
                    }),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Open Expansion Lab',
                    icon: Icons.rocket_launch_outlined,
                    onPressed: () => _open(const AdminExpansionLabScreen()),
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
                    title: 'Autopilot Risk Overlay',
                    subtitle: 'Recommendations with risk flags before activation.',
                  ),
                  const SizedBox(height: 8),
                  if (overlay.isEmpty)
                    const Text('No risk overlay items in latest snapshot.')
                  else
                    ...overlay.take(4).map((row) {
                      if (row is! Map) return const SizedBox.shrink();
                      final flags = (row['risk_flags'] is List)
                          ? (row['risk_flags'] as List).join(', ')
                          : '';
                      return Text('- ${row['title'] ?? ''}  [$flags]');
                    }),
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'Open Autopilot',
                    icon: Icons.auto_awesome_outlined,
                    onPressed: () => _open(const AdminAutopilotScreen()),
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

Widget _skeletonCard(BuildContext context, int _) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: FTSkeletonCard(height: 120),
  );
}
