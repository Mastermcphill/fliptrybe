import 'package:flutter/material.dart';

import '../design/ft_tokens.dart';

class FTCard extends StatelessWidget {
  const FTCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = FTDesignTokens.e1,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double elevation;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: FTDesignTokens.d150,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius:
            borderRadius ?? BorderRadius.circular(FTDesignTokens.radiusMd),
        boxShadow: FTDesignTokens.elevationShadows(scheme, elevation),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(FTDesignTokens.md),
        child: child,
      ),
    );
  }
}
