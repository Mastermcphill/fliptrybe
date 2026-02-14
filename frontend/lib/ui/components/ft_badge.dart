import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';

class FTBadge extends StatelessWidget {
  const FTBadge({
    super.key,
    required this.text,
    this.backgroundColor,
    this.foregroundColor,
    this.bgColor,
    this.textColor,
  });

  final String text;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? bgColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.s8, vertical: AppTokens.s4),
      decoration: BoxDecoration(
        color: bgColor ?? backgroundColor ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color:
                  textColor ?? foregroundColor ?? scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class FTPill extends FTBadge {
  const FTPill({
    super.key,
    required super.text,
    super.backgroundColor,
    super.foregroundColor,
    super.bgColor,
    super.textColor,
  });
}
