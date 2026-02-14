import 'package:flutter/material.dart';

Future<void> showChatNotAllowedDialog(
  BuildContext context, {
  VoidCallback? onChatWithAdmin,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Chat limited to Admin'),
        content:
            const Text('To keep FlipTrybe safe, you can only chat with Admin.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: onChatWithAdmin == null
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    onChatWithAdmin();
                  },
            child: const Text('Chat with Admin'),
          ),
        ],
      );
    },
  );
}
