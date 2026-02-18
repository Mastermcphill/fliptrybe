import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/services/api_service.dart';
import 'package:fliptrybe/utils/role_gates.dart';

void main() {
  testWidgets('Sell attempt without phone verification shows phone prompt',
      (tester) async {
    ApiService.setToken('test-token');
    addTearDown(() => ApiService.setToken(null));

    var called = 0;
    final profile = <String, dynamic>{
      'role': 'merchant',
      'role_status': 'approved',
      'is_verified': false,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    guardRestrictedAction(
                      context,
                      block: RoleGates.forPostListing(profile),
                      onAllowed: () async {
                        called += 1;
                      },
                    );
                  },
                  child: const Text('Sell'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('Phone verification required'), findsOneWidget);
    expect(called, 0);
  });

  testWidgets('Sell attempt with phone verification proceeds', (tester) async {
    ApiService.setToken('test-token');
    addTearDown(() => ApiService.setToken(null));

    var called = 0;
    final profile = <String, dynamic>{
      'role': 'merchant',
      'role_status': 'approved',
      'is_verified': true,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    guardRestrictedAction(
                      context,
                      block: RoleGates.forPostListing(profile),
                      onAllowed: () async {
                        called += 1;
                      },
                    );
                  },
                  child: const Text('Sell'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('Phone verification required'), findsNothing);
    expect(called, 1);
  });

  testWidgets('Role gate blocks restricted action with guidance message',
      (tester) async {
    ApiService.setToken('test-token');
    addTearDown(() => ApiService.setToken(null));

    var called = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    guardRestrictedAction(
                      context,
                      block: const RoleGateBlock(
                        title: 'KYC required',
                        message: 'Complete KYC to continue.',
                        primaryCta: 'Complete KYC',
                      ),
                      onAllowed: () async {
                        called += 1;
                      },
                    );
                  },
                  child: const Text('Run Action'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Run Action'));
    await tester.pumpAndSettle();

    expect(find.text('KYC required'), findsOneWidget);
    expect(find.text('Complete KYC to continue.'), findsOneWidget);
    expect(called, 0);
  });
}
