import 'package:flutter/material.dart';

import '../design/ft_tokens.dart';
import 'ft_button.dart';

class FTEmptyState extends StatelessWidget {
  const FTEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.primaryCtaText,
    this.onPrimaryCta,
    this.secondaryCtaText,
    this.onSecondaryCta,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? primaryCtaText;
  final VoidCallback? onPrimaryCta;
  final String? secondaryCtaText;
  final VoidCallback? onSecondaryCta;

  // Backward compatibility aliases.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryLabel = primaryCtaText ?? actionLabel;
    final primaryAction = onPrimaryCta ?? onAction;
    final hasPrimary =
        (primaryLabel ?? '').trim().isNotEmpty && primaryAction != null;
    final hasSecondary =
        (secondaryCtaText ?? '').trim().isNotEmpty && onSecondaryCta != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FTDesignTokens.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: scheme.onSurfaceVariant),
              const SizedBox(height: FTDesignTokens.sm),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FTDesignTokens.xs),
              Text(
                subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (hasPrimary || hasSecondary) ...[
                const SizedBox(height: FTDesignTokens.md),
                if (hasPrimary)
                  FTPrimaryButton(
                    label: primaryLabel!,
                    onPressed: primaryAction,
                  ),
                if (hasSecondary) ...[
                  const SizedBox(height: FTDesignTokens.sm),
                  FTButton(
                    label: secondaryCtaText!,
                    onPressed: onSecondaryCta,
                    variant: FTButtonVariant.secondary,
                    expand: true,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FTErrorState extends StatelessWidget {
  const FTErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FTEmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      subtitle: message,
      primaryCtaText: onRetry == null ? null : 'Retry',
      onPrimaryCta: onRetry,
    );
  }
}
