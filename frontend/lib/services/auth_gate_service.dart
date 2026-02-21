import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/role_signup_screen.dart';
import '../ui/foundation/components/components.dart';
import '../ui/foundation/tokens/ft_spacing.dart';
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

  final choice = await FTBottomSheet.show<_AuthGateChoice>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FTSpacing.sm,
          FTSpacing.xs,
          FTSpacing.sm,
          FTSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sign in required',
              style: Theme.of(ctx)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: FTSpacing.xs),
            Text(
              'You can browse freely. Sign in to $action.',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: FTSpacing.sm),
            FTButton(
              label: 'Login',
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(_AuthGateChoice.login),
            ),
            const SizedBox(height: FTSpacing.xs),
            FTButton(
              label: 'Create account',
              expand: true,
              variant: FTButtonVariant.secondary,
              onPressed: () => Navigator.of(ctx).pop(_AuthGateChoice.signup),
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
