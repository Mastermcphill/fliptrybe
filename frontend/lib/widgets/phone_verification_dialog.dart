import 'package:flutter/material.dart';

Future<void> showPhoneVerificationRequiredDialog(
  BuildContext context, {
  String? message,
  Future<void> Function()? onRetry,
}) async {
  final msg = (message == null || message.trim().isEmpty)
      ? 'Phone verification required to continue.'
      : message.trim();

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Phone verification required'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
          TextButton(
            onPressed: onRetry == null
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    await onRetry();
                  },
            child: const Text('Retry'),
          ),
        ],
      );
    },
  );
}
