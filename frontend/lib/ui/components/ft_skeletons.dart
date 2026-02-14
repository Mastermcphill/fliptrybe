import 'package:flutter/material.dart';

import '../design/ft_tokens.dart';
import 'ft_card.dart';

class FTSkeletonLine extends StatelessWidget {
  const FTSkeletonLine({
    super.key,
    this.height = 12,
    this.widthFactor = 1,
    this.radius,
  });

  final double height;
  final double widthFactor;
  final BorderRadiusGeometry? radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final clamped = widthFactor.clamp(0.1, 1.0);
        return Container(
          height: height,
          width: maxWidth * clamped,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.08),
            borderRadius: radius ?? FTDesignTokens.roundedSm,
          ),
        );
      },
    );
  }
}

class FTSkeletonCard extends StatelessWidget {
  const FTSkeletonCard({
    super.key,
    this.height = 140,
    this.padding = const EdgeInsets.symmetric(
        horizontal: FTDesignTokens.md, vertical: FTDesignTokens.sm),
    this.child,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: FTCard(
        child: SizedBox(
          height: height,
          child: child ??
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FTSkeletonLine(height: 14, widthFactor: 0.55),
                  SizedBox(height: FTDesignTokens.sm),
                  FTSkeletonLine(height: 12),
                  SizedBox(height: FTDesignTokens.xs),
                  FTSkeletonLine(height: 12, widthFactor: 0.75),
                ],
              ),
        ),
      ),
    );
  }
}

class FTSkeletonList extends StatelessWidget {
  const FTSkeletonList({
    super.key,
    this.itemCount = 4,
    this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(vertical: FTDesignTokens.sm),
  });

  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: FTDesignTokens.xs),
      itemBuilder: (context, index) {
        if (itemBuilder != null) {
          return itemBuilder!(context, index);
        }
        return const FTSkeletonCard(height: 104);
      },
    );
  }
}

class FTSkeletonGrid extends StatelessWidget {
  const FTSkeletonGrid({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
    this.childAspectRatio = 0.82,
    this.padding = const EdgeInsets.all(FTDesignTokens.md),
  });

  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: FTDesignTokens.sm,
        mainAxisSpacing: FTDesignTokens.sm,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const FTCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: FTSkeletonLine(height: double.infinity)),
            SizedBox(height: FTDesignTokens.sm),
            FTSkeletonLine(height: 12, widthFactor: 0.7),
            SizedBox(height: FTDesignTokens.xs),
            FTSkeletonLine(height: 12, widthFactor: 0.5),
          ],
        ),
      ),
      shrinkWrap: true,
    );
  }
}
