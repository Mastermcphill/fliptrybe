import 'package:fliptrybe/screens/admin_payout_console_screen.dart';
import 'package:fliptrybe/services/admin_wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdminWalletService extends AdminWalletService {
  int payCalls = 0;

  @override
  Future<List<dynamic>> listPayouts({String status = ''}) async {
    return <dynamic>[
      <String, dynamic>{
        'id': 42,
        'user_id': 7,
        'amount': 1500,
        'status': status.isEmpty ? 'pending' : status,
      },
    ];
  }

  @override
  Future<bool> pay(int payoutId) async {
    payCalls += 1;
    return true;
  }

  @override
  Future<bool> approve(int payoutId) async => true;

  @override
  Future<bool> reject(int payoutId) async => true;

  @override
  Future<bool> process(int payoutId) async => true;

  @override
  Future<bool> markPaid(int payoutId) async => true;
}

void main() {
  testWidgets('payout provider action calls service once and reports success',
      (tester) async {
    final fake = _FakeAdminWalletService();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminPayoutConsoleScreen(service: fake),
      ),
    );
    await tester.pumpAndSettle();

    expect(fake.payCalls, 0);
    expect(find.text('Process Provider Payout'), findsOneWidget);

    await tester.tap(find.text('Process Provider Payout'));
    await tester.pumpAndSettle();

    expect(fake.payCalls, 1);
    expect(find.text('Provider payout processed.'), findsOneWidget);
  });
}
