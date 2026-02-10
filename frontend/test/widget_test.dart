import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/screens/landing_screen.dart';
import 'package:fliptrybe/screens/role_signup_screen.dart';

void main() {
  testWidgets('MaterialApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox.shrink(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Landing signup CTA routes to role chooser', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => LandingScreen(
            enableTicker: false,
            onLogin: () {},
            onSignup: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
              );
            },
          ),
        ),
      ),
    );

    final signupFinder = find.text('Sign up (Choose role)');
    await tester.ensureVisible(signupFinder);
    await tester.pumpAndSettle();
    await tester.tap(signupFinder);
    await tester.pumpAndSettle();

    expect(find.byType(RoleSignupScreen), findsOneWidget);
  });
}
