import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/role_signup_screen.dart';
import 'api_service.dart';
import 'token_storage.dart';

enum _AuthGateChoice { login, signup }

class AuthGateService {
  static Future<bool> isAuthenticated() async {
    final inMemory = (ApiService.token ?? '').trim();
    if (inMemory.isNotEmpty) return true;
    final stored = (await TokenStorage().readToken() ?? '').trim();
    return stored.isNotEmpty;
  }
}

Future<bool> requireAuthForAction(
  BuildContext context, {
  required String action,
  required Future<void> Function() onAuthorized,
}) async {
  final authenticated = await AuthGateService.isAuthenticated();
  if (authenticated) {
    await onAuthorized();
    return true;
  }
  if (!context.mounted) return false;

  final choice = await showModalBottomSheet<_AuthGateChoice>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sign in required',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'You can browse freely. Sign in to $action.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(_AuthGateChoice.login),
                child: const Text('Login'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(_AuthGateChoice.signup),
                child: const Text('Create account'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted || choice == null) return false;

  if (choice == _AuthGateChoice.login) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  } else {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RoleSignupScreen()),
    );
  }
  final refreshed = await AuthGateService.isAuthenticated();
  if (!refreshed || !context.mounted) return false;
  await onAuthorized();
  return true;
}
