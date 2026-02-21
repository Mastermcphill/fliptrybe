import 'package:flutter/material.dart';

import '../foundation/tokens/ft_spacing.dart';
import 'ft_card.dart';

class FTSkeleton extends StatelessWidget {
  const FTSkeleton({
    super.key,
    this.height = 14,
    this.width,
    this.borderRadius,
  });

  final double height;
  final double? width;
  final BorderRadiusGeometry? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: borderRadius ?? BorderRadius.circular(FTSpacing.xs),
      ),
    );
  }
}

class FTMetricSkeletonTile extends StatelessWidget {
  const FTMetricSkeletonTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTSkeleton(height: 12, width: 96),
          SizedBox(height: FTSpacing.xs),
          FTSkeleton(height: 22, width: 120),
          SizedBox(height: FTSpacing.xs),
          FTSkeleton(height: 12, width: 140),
        ],
      ),
    );
  }
}

class FTListCardSkeleton extends StatelessWidget {
  const FTListCardSkeleton({super.key, this.withImage = true});

  final bool withImage;

  @override
  Widget build(BuildContext context) {
    return FTCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withImage) ...[
            const FTSkeleton(height: 72, width: 72),
            const SizedBox(width: FTSpacing.xs),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FTSkeleton(height: 14, width: 150),
                SizedBox(height: FTSpacing.xs),
                FTSkeleton(height: 12),
                SizedBox(height: FTSpacing.xs),
                FTSkeleton(height: 12, width: 120),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
