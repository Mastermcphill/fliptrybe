import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/api_client.dart';
import '../services/api_service.dart';
import '../widgets/app_exit_guard.dart';

Future<void> logoutToLanding(
  BuildContext context, {
  Future<void> Function()? resetAuthSessionCall,
}) async {
  FocusManager.instance.primaryFocus?.unfocus();
  ScaffoldMessenger.maybeOf(context)?.clearSnackBars();

  final rootNavigator = Navigator.of(context, rootNavigator: true);
  try {
    rootNavigator.popUntil((route) => route is PageRoute);
  } catch (_) {
    // Best effort: if there is no overlay route to pop, continue.
  }

  // Immediately clear in-memory auth headers/cancelled requests before
  // persistent/session cleanup to avoid stale-client reuse.
  ApiClient.instance.resetSession();
  await (resetAuthSessionCall?.call() ?? ApiService.resetAuthSession());
  if (!context.mounted) return;

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => const AppExitGuard(child: LoginScreen()),
    ),
    (_) => false,
  );
}
