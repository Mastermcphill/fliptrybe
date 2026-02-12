import 'package:flutter/material.dart';

import '../../ui/components/ft_components.dart';
import 'role_growth_calculator.dart';

class GrowthAnalyticsScreen extends StatelessWidget {
  const GrowthAnalyticsScreen({
    super.key,
    required this.role,
  });

  final String role;

  String _title() {
    final r = role.toLowerCase();
    if (r == 'merchant') return 'Merchant Growth Analytics';
    if (r == 'driver') return 'Driver Growth Analytics';
    if (r == 'inspector') return 'Inspector Growth Analytics';
    return 'Growth Analytics';
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: _title(),
      child: RoleGrowthCalculator(role: role),
    );
  }
}
