import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';
import 'ft_badge.dart';

class FTTile extends StatelessWidget {
  const FTTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.badgeText,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final String? badgeText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.r12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s12,
          vertical: AppTokens.s12,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              Icon(leading, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppTokens.s12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTokens.s4),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            if (badgeText != null && badgeText!.trim().isNotEmpty) ...[
              FTBadge(text: badgeText!),
              const SizedBox(width: AppTokens.s8),
            ],
            trailing ?? Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
