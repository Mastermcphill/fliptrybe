import 'package:flutter/material.dart';

import '../foundation/tokens/ft_motion.dart';
import '../foundation/tokens/ft_radius.dart';
import '../foundation/tokens/ft_shadows.dart';
import '../foundation/tokens/ft_spacing.dart';

class FTCard extends StatelessWidget {
  const FTCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.elevation = 1,
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
      duration: FTMotion.quick,
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: borderRadius ?? FTRadius.roundedMd,
        boxShadow: elevation > 0 ? FTShadows.subtle(scheme) : FTShadows.none(),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(FTSpacing.sm),
        child: child,
      ),
    );
  }
}
