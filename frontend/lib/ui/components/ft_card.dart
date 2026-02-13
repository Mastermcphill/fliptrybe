import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';

class FTCard extends StatelessWidget {
  const FTCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = AppTokens.e1,
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
      duration: AppTokens.d150,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: borderRadius ?? BorderRadius.circular(AppTokens.r16),
        boxShadow: AppTokens.elevationShadows(scheme, elevation),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppTokens.s16),
        child: child,
      ),
    );
  }
}
