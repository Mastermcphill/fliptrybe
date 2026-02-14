import 'package:fliptrybe/screens/admin_autopilot_screen.dart';
import 'package:fliptrybe/services/admin_autopilot_service.dart';
import 'package:fliptrybe/ui/components/ft_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAutopilotService extends AdminAutopilotService {
  bool hasRun = false;

  @override
  Future<Map<String, dynamic>> status() async {
    return {
      'ok': true,
      'settings': {
        'enabled': true,
        'payments_provider': 'mock',
        'integrations_mode': 'sandbox',
        'search_v2_mode': 'off',
        'integrations': {},
        'features': {},
        'integration_health': {},
      }
    };
  }

  @override
  Future<Map<String, dynamic>> getPaymentsMode() async {
    return {
      'ok': true,
      'settings': {'mode': 'mock'}
    };
  }

  @override
  Future<Map<String, dynamic>> getPaymentsSettings() async {
    return {
      'ok': true,
      'settings': {
        'mode': 'mock',
        'manual_payment_sla_minutes': 360,
      }
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listSnapshots({int limit = 20}) async {
    if (hasRun) {
      return [
        {
          'id': 2,
          'window_days': 30,
          'draft_policy_id': null,
          'recommendations_count': 1,
        }
      ];
    }
    return [
      {
        'id': 1,
        'window_days': 30,
        'draft_policy_id': null,
        'recommendations_count': 0,
      }
    ];
  }

  @override
  Future<Map<String, dynamic>> getRecommendations({int? snapshotId}) async {
    if (hasRun) {
      return {
        'ok': true,
        'snapshot': {'id': 2, 'window_days': 30},
        'items': [
          {
            'id': 99,
            'status': 'new',
            'recommendation': {
              'title': 'Increase commission by 0.50% for Declutter / Lagos',
              'confidence': 'high',
              'risk_flags': ['LIQUIDITY_RISK_ELEVATED'],
              'explanation': ['Payout pressure is elevated'],
              'expected_impact': {
                'revenue_delta_minor': 12000,
                'gmv_delta_minor': -3400,
              }
            }
          }
        ],
      };
    }
    return {
      'ok': true,
      'snapshot': {'id': 1, 'window_days': 30},
      'items': [],
    };
  }

  @override
  Future<Map<String, dynamic>> runAutopilot({required int window}) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    hasRun = true;
    return {
      'ok': true,
      'snapshot': {'id': 2, 'window_days': window},
      'recommendations': const [],
      'idempotent': false,
    };
  }

  @override
  Future<Map<String, dynamic>> updateRecommendationStatus({
    required int recommendationId,
    required String status,
  }) async {
    return {'ok': true};
  }
}

class _RecommendationHarness extends StatefulWidget {
  const _RecommendationHarness();

  @override
  State<_RecommendationHarness> createState() => _RecommendationHarnessState();
}

class _RecommendationHarnessState extends State<_RecommendationHarness> {
  String status = 'new';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: AutopilotRecommendationCard(
          title: 'Reduce commission by 0.50%',
          status: status,
          confidence: 'high',
          riskFlags: const ['SUPPLY_CONSTRAINT'],
          explanation: const ['Supply is constrained in this segment.'],
          revenueDeltaMinor: -2200,
          gmvDeltaMinor: 4000,
          onAccept: () => setState(() => status = 'accepted'),
          onDismiss: () => setState(() => status = 'dismissed'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('autopilot recommendation accept/dismiss toggles persist in UI',
      (tester) async {
    await tester.pumpWidget(const _RecommendationHarness());
    expect(find.textContaining('Status: new'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: accepted'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: dismissed'), findsOneWidget);
  });

  testWidgets('run autopilot shows skeleton then results', (tester) async {
    final fake = _FakeAutopilotService();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminAutopilotScreen(service: fake),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Run Autopilot'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Run Autopilot'), findsOneWidget);

    await tester.tap(find.text('Run Autopilot'));
    await tester.pump();
    expect(find.byType(FTSkeletonCard), findsWidgets);

    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
    expect(find.textContaining('Increase commission by 0.50%'), findsOneWidget);
  });
}
