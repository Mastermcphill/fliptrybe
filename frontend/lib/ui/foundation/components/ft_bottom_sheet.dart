import 'dart:ui';

import 'package:flutter/material.dart';

import '../tokens/ft_radius.dart';
import '../tokens/ft_spacing.dart';

class FTBottomSheet {
  const FTBottomSheet._();

  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useSafeArea = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FTRadius.lg),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.96),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FTRadius.lg),
                ),
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FTSpacing.sm,
                  FTSpacing.sm,
                  FTSpacing.sm,
                  FTSpacing.sm,
                ),
                child: builder(sheetContext),
              ),
            ),
          ),
        );
      },
    );
  }
}
