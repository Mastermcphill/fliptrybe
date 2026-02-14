import 'package:flutter/material.dart';

class FTDivider extends StatelessWidget {
  const FTDivider({
    super.key,
    this.height = 1,
    this.margin,
  });

  final double height;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      margin: margin,
      height: height,
      color: color,
    );
  }
}
