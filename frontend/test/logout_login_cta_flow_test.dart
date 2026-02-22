import 'package:fliptrybe/screens/login_screen.dart';
import 'package:fliptrybe/screens/role_signup_screen.dart';
import 'package:fliptrybe/utils/auth_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LogoutHarness extends StatelessWidget {
  const _LogoutHarness({
    required this.resetAuthSessionCall,
  });

  final Future<void> Function() resetAuthSessionCall;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => logoutToLanding(
            context,
            resetAuthSessionCall: resetAuthSessionCall,
          ),
          child: const Text('Sign out'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'logout keeps login/signup actions responsive without app restart',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _LogoutHarness(
            resetAuthSessionCall: () async {},
          ),
        ),
      );

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Create Account'), findsOneWidget);

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(find.byType(RoleSignupScreen), findsOneWidget);
      expect(find.text('Choose your path'), findsOneWidget);
    },
  );
}
