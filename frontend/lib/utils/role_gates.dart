import 'package:flutter/material.dart';

import '../services/auth_gate_service.dart';
import '../ui/components/ft_components.dart';

class RoleGateBlock {
  const RoleGateBlock({
    required this.title,
    required this.message,
    required this.primaryCta,
  });

  final String title;
  final String message;
  final String primaryCta;
}

class RoleGates {
  const RoleGates._();

  static bool canAccessAdmin(Map<String, dynamic>? user) {
    final role = (user?['role'] ?? '').toString().toLowerCase();
    return role == 'admin';
  }

  static bool canPostListing(Map<String, dynamic>? user) {
    final role = (user?['role'] ?? '').toString().toLowerCase();
    final status =
        (user?['role_status'] ?? user?['role_request_status'] ?? 'approved')
            .toString()
            .toLowerCase();
    return (role == 'merchant' || role == 'admin') &&
        status == 'approved' &&
        !requiresPhoneVerified(user);
  }

  static bool canWithdraw(Map<String, dynamic>? user) {
    final role = (user?['role'] ?? '').toString().toLowerCase();
    final hasMoneyRole = role == 'merchant' ||
        role == 'driver' ||
        role == 'inspector' ||
        role == 'admin';
    if (!hasMoneyRole) return false;
    if (requiresPhoneVerified(user)) return false;
    if (requiresKycTier(user)) return false;
    return true;
  }

  static bool requiresPhoneVerified(Map<String, dynamic>? user) {
    final value = user?['is_verified'];
    return value != true;
  }

  static bool requiresKycTier(Map<String, dynamic>? user, {int minTier = 2}) {
    final dynamic tierRaw = user?['tier'];
    final int tier = int.tryParse((tierRaw ?? '').toString()) ?? 0;
    final dynamic kycRaw = user?['kyc_verified'] ?? user?['kyc_ok'];
    final bool kycOk = kycRaw == true;
    return !kycOk || tier < minTier;
  }

  static RoleGateBlock? forPostListing(Map<String, dynamic>? user) {
    if (user == null || user.isEmpty) {
      return const RoleGateBlock(
        title: 'Sign in required',
        message: 'Create an account to post listings in Marketplace.',
        primaryCta: 'Log in',
      );
    }
    if (requiresPhoneVerified(user)) {
      return const RoleGateBlock(
        title: 'Phone verification required',
        message: 'Verify your phone before posting listings.',
        primaryCta: 'Verify phone',
      );
    }
    if (!canPostListing(user)) {
      return const RoleGateBlock(
        title: 'Merchant approval required',
        message:
            'Your merchant role is pending. Complete approval to post listings.',
        primaryCta: 'Open Role Status',
      );
    }
    return null;
  }

  static RoleGateBlock? forWithdraw(Map<String, dynamic>? user) {
    if (user == null || user.isEmpty) {
      return const RoleGateBlock(
        title: 'Sign in required',
        message: 'Sign in to access withdrawals.',
        primaryCta: 'Log in',
      );
    }
    if (requiresPhoneVerified(user)) {
      return const RoleGateBlock(
        title: 'Phone verification required',
        message: 'Verify your phone before requesting withdrawals.',
        primaryCta: 'Verify phone',
      );
    }
    if (requiresKycTier(user)) {
      return const RoleGateBlock(
        title: 'Tier upgrade required',
        message: 'Complete KYC and upgrade your tier to unlock withdrawals.',
        primaryCta: 'Complete KYC',
      );
    }
    if (!canWithdraw(user)) {
      return const RoleGateBlock(
        title: 'Action unavailable',
        message: 'Your current role cannot perform withdrawals.',
        primaryCta: 'Got it',
      );
    }
    return null;
  }

  static RoleGateBlock? forAdminAccess(Map<String, dynamic>? user) {
    if (canAccessAdmin(user)) return null;
    return const RoleGateBlock(
      title: 'Admin access required',
      message: 'This area is restricted to admin operators.',
      primaryCta: 'Return',
    );
  }
}

Future<bool> guardRestrictedAction(
  BuildContext context, {
  required RoleGateBlock? block,
  required Future<void> Function() onAllowed,
  String authAction = 'continue',
}) async {
  if (block == null) {
    await onAllowed();
    return true;
  }

  final authenticated = await AuthGateService.isAuthenticated();
  if (!authenticated && context.mounted) {
    return requireAuthForAction(
      context,
      action: authAction,
      onAuthorized: onAllowed,
    );
  }

  if (!context.mounted) return false;

  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FTEmptyState(
            icon: Icons.lock_outline,
            title: block.title,
            subtitle: block.message,
            primaryCtaText: block.primaryCta,
            onPrimaryCta: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      );
    },
  );
  return false;
}
