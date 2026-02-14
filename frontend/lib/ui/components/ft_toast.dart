import 'package:flutter/material.dart';

class FTToast {
  const FTToast._();

  static void show(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 2),
  }) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: duration,
        backgroundColor: scheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
