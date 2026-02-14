import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fliptrybe/screens/login_screen.dart';

void main() {
  testWidgets('login submit is locked while request is in flight',
      (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    var callCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          loginAction: (email, password) {
            callCount += 1;
            return completer.future;
          },
          meAction: () async => <String, dynamic>{
            'role': 'buyer',
            'role_status': 'pending',
          },
        ),
      ),
    );

    final fields = find.byType(TextField);
    expect(fields, findsAtLeastNWidgets(2));

    await tester.enterText(fields.at(0), 'tester@fliptrybe.com');
    await tester.enterText(fields.at(1), 'secret123');

    final loginButton = find.widgetWithText(TextButton, 'Login');
    expect(loginButton, findsOneWidget);

    await tester.tap(loginButton);
    await tester.pump();

    expect(callCount, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(loginButton);
    await tester.pump();
    expect(callCount, 1);

    completer.complete(<String, dynamic>{
      'token': 'token_123',
    });

    await tester.pumpAndSettle();
    expect(find.text('Pending Approval'), findsOneWidget);
  });
}
