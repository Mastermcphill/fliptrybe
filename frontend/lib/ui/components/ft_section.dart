import 'package:flutter/material.dart';

import '../design/ft_tokens.dart';
import 'ft_card.dart';

class FTSection extends StatelessWidget {
  const FTSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.margin,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return FTCard(
      margin: margin,
      padding: const EdgeInsets.all(FTDesignTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if ((subtitle ?? '').trim().isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(top: FTDesignTokens.xs / 2),
                        child: Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: FTDesignTokens.sm),
                Flexible(child: action!),
              ],
            ],
          ),
          const SizedBox(height: FTDesignTokens.sm),
          child,
        ],
      ),
    );
  }
}
