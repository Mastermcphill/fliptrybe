import 'package:flutter/material.dart';

import '../components/ft_card.dart';
import '../foundation/app_tokens.dart';

class AdminMetricCard extends StatelessWidget {
  const AdminMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (icon != null) Icon(icon, size: 16, color: scheme.primary),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Text(value, style: Theme.of(context).textTheme.displaySmall),
          if ((subtitle ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child:
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
