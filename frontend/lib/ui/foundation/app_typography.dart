import 'package:flutter/material.dart';

import 'tokens/ft_typography.dart' as foundation;

class AppTypography {
  const AppTypography._();

  static TextTheme textTheme(ColorScheme scheme) =>
      foundation.FTTypography.textTheme(scheme);

  static TextStyle pageTitle(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!;

  static TextStyle sectionTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!;

  static TextStyle cardTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!;

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!;

  static TextStyle meta(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall!;

  static TextStyle price(BuildContext context) =>
      Theme.of(context).textTheme.displaySmall!;
}
