import 'package:flutter/material.dart';

class UnavailableAction {
  const UnavailableAction._();

  static void showReasonSnack(
    BuildContext context,
    String reason, {
    String fallback = 'This action is not available yet.',
  }) {
    final message = reason.trim().isEmpty ? fallback : reason.trim();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class UnavailableActionHint extends StatelessWidget {
  const UnavailableActionHint({
    super.key,
    required this.reason,
    this.icon = Icons.info_outline,
  });

  final String reason;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (reason.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reason.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
