import 'package:flutter/material.dart';

import '../screens/email_verify_screen.dart';
import '../services/api_service.dart';

Future<void> showEmailVerificationRequiredDialog(
  BuildContext context, {
  String? message,
  Future<void> Function()? onRetry,
}) async {
  final msg = (message == null || message.trim().isEmpty)
      ? 'Email verification required to continue.'
      : message.trim();

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      bool sending = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Email verification required'),
            content: Text(
              msg,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Dismiss'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EmailVerifyScreen()),
                  );
                },
                child: const Text('Verify Email'),
              ),
              TextButton(
                onPressed: onRetry == null
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        await onRetry();
                      },
                child: const Text("I've verified, retry"),
              ),
              ElevatedButton(
                onPressed: sending
                    ? null
                    : () async {
                        try {
                          setState(() => sending = true);
                          await ApiService.verifySend();
                          if (!context.mounted) return;
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verification link sent. Check your inbox or server logs.')),
                          );
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Resend failed: $e')),
                          );
                        } finally {
                          if (context.mounted) setState(() => sending = false);
                        }
                      },
                child: Text(sending ? 'Sending...' : 'Resend verification'),
              ),
            ],
          );
        },
      );
    },
  );
}
