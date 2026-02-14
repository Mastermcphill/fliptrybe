import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/omega_intelligence_service.dart';
import 'package:fliptrybe/screens/admin_elasticity_dashboard_screen.dart';
import 'package:fliptrybe/screens/admin_expansion_lab_screen.dart';
import 'package:fliptrybe/screens/admin_fraud_center_screen.dart';
import 'package:fliptrybe/ui/components/ft_components.dart';

class _FakeOmegaService extends OmegaIntelligenceService {
  bool freezeCalled = false;
  List<Map<String, dynamic>> seededFlags = const [
    {
      'id': 9,
      'user_id': 12,
      'score': 88,
      'status': 'open',
      'level': 'freeze',
      'reasons': {
        'items': [
          {'code': 'SELF_REFERRAL_PATTERN', 'weight': 95}
        ]
      },
      'user': {
        'id': 12,
        'name': 'Risk User',
        'email': 'risk@fliptrybe.test',
      }
    }
  ];

  @override
  Future<List<Map<String, dynamic>>> fraudFlags({
    bool refresh = true,
    String status = 'open_only',
    int minScore = 30,
    int limit = 100,
    int offset = 0,
  }) async {
    return seededFlags;
  }

  @override
  Future<Map<String, dynamic>> freezeFraudFlag({
    required int fraudFlagId,
    String note = '',
  }) async {
    freezeCalled = true;
    return {
      'ok': true,
      'flag': {'id': fraudFlagId, 'status': 'action_taken'}
    };
  }

  @override
  Future<Map<String, dynamic>> reviewFraudFlag({
    required int fraudFlagId,
    required String status,
    String note = '',
  }) async {
    return {
      'ok': true,
      'flag': {'id': fraudFlagId, 'status': status}
    };
  }
}

void main() {
  testWidgets('Fraud freeze button opens confirmation modal', (tester) async {
    final fakeService = _FakeOmegaService();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminFraudCenterScreen(
          service: fakeService,
          autoLoad: false,
          initialFlags: fakeService.seededFlags,
        ),
      ),
    );

    expect(find.text('Freeze account'), findsOneWidget);
    await tester.tap(find.text('Freeze account'));
    await tester.pumpAndSettle();
    expect(find.text('Freeze account'), findsNWidgets(2));
    expect(find.textContaining('Continue'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Freeze'));
    await tester.pumpAndSettle();
    expect(fakeService.freezeCalled, isTrue);
  });

  testWidgets('Elasticity dashboard renders conversion curve chart',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminElasticityDashboardScreen(
          autoLoad: false,
          initialData: {
            'elasticity_coefficient': -0.82,
            'price_sensitivity': 'medium',
            'recommended_price_shift_pct': -2.5,
            'confidence': 'high',
            'sample_size': 140,
            'conversion_curve': [
              {'price_mid_minor': 100000, 'conversion_proxy': 0.7},
              {'price_mid_minor': 150000, 'conversion_proxy': 0.52},
              {'price_mid_minor': 200000, 'conversion_proxy': 0.33},
            ],
            'explanation': ['Deterministic test payload']
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Elasticity Dashboard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Conversion Curve'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Conversion Curve'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.byType(FTMetricTile), findsWidgets);
  });

  testWidgets('Expansion simulation output renders values', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminExpansionLabScreen(
          initialResult: {
            'projected_6_month_gmv_minor': 4500000000,
            'projected_commission_revenue_minor': 225000000,
            'cac_break_even_days': 71,
            'roi_projection_pct': 14.25,
            'liquidity_stress_indicator': false,
            'confidence_score': 'medium',
            'unit_economics': {
              'estimated_cac_minor': 800000,
              'ltv_estimation_minor': 2560000,
            }
          },
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Expansion Lab'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Projected 6-month GMV'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Projected 6-month GMV'), findsOneWidget);
    expect(find.byType(FTMetricTile), findsWidgets);
    expect(find.textContaining('ROI projection'), findsWidgets);
  });
}
