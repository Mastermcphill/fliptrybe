import 'package:flutter/material.dart';

import '../foundation/tokens/ft_typography.dart' as foundation;

class FTTypography {
  const FTTypography._();

  static TextTheme textTheme(ColorScheme scheme) =>
      foundation.FTTypography.textTheme(scheme);

  static TextStyle headline(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!;

  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!;

  static TextStyle muted(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;
}
