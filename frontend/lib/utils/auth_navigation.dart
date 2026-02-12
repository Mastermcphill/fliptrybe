import 'package:flutter/material.dart';

import '../screens/landing_screen.dart';
import '../screens/login_screen.dart';
import '../screens/role_signup_screen.dart';
import '../services/api_service.dart';

Future<void> logoutToLanding(BuildContext context) async {
  FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();

  final rootNavigator = Navigator.of(context, rootNavigator: true);
  try {
    rootNavigator.popUntil((route) => route is PageRoute);
  } catch (_) {
    // Best effort: if there is no overlay route to pop, continue.
  }

  await ApiService.resetAuthSession();
  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (landingContext) => LandingScreen(
        onLogin: () {
          Navigator.of(landingContext).push(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        },
        onSignup: () {
          Navigator.of(landingContext).push(
            MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
          );
        },
      ),
    ),
    (_) => false,
  );
}
