import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/ui/components/ft_money_confirmation_sheet.dart';
import 'package:fliptrybe/utils/formatters.dart';

void main() {
  testWidgets('Money confirmation sheet renders amount, fee and total',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showMoneyConfirmationSheet(
                    context,
                    const FTMoneyConfirmationPayload(
                      title: 'Confirm payment',
                      amount: 1000,
                      fee: 100,
                      total: 1100,
                      destination: 'Wallet balance',
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm payment'), findsOneWidget);
    expect(find.text(formatNaira(1000)), findsOneWidget);
    expect(find.text(formatNaira(100)), findsOneWidget);
    expect(find.text(formatNaira(1100)), findsOneWidget);
    expect(find.text('Wallet balance'), findsOneWidget);
  });
}
