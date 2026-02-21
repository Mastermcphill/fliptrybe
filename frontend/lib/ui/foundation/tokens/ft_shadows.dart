import 'package:flutter/material.dart';

class FTShadows {
  const FTShadows._();

  static List<BoxShadow> subtle(ColorScheme scheme) {
    return <BoxShadow>[
      BoxShadow(
        color: scheme.shadow.withValues(alpha: 0.06),
        blurRadius: 14,
        offset: const Offset(0, 4),
      ),
    ];
  }

  static List<BoxShadow> none() => const <BoxShadow>[];
}
