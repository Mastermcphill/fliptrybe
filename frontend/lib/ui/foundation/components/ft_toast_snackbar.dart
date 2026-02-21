import 'package:flutter/material.dart';

import '../../components/ft_toast.dart';

class FTToastSnackbar {
  const FTToastSnackbar._();

  static void show(
    BuildContext context,
    String message, {
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 2),
  }) {
    FTToast.show(
      context,
      message,
      action: action,
      duration: duration,
    );
  }

  static void showError(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: scheme.error,
        ),
      );
  }
}
