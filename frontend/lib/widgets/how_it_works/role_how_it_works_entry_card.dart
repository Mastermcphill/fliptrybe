import 'package:flutter/material.dart';

import '../../screens/how_it_works/role_how_it_works_screen.dart';

class RoleHowItWorksEntryCard extends StatelessWidget {
  const RoleHowItWorksEntryCard({
    super.key,
    required this.role,
    this.onTap,
  });

  final String role;
  final VoidCallback? onTap;

  String _label(String value) {
    switch (value.toLowerCase()) {
      case 'merchant':
        return 'Merchant';
      case 'driver':
        return 'Driver';
      case 'inspector':
        return 'Inspector';
      default:
        return 'Role';
    }
  }

  void _defaultOpen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RoleHowItWorksScreen(role: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: Text('How FlipTrybe Works (${_label(role)})'),
        subtitle: const Text(
          'Understand earnings, escrow, commissions and MoneyBox.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? () => _defaultOpen(context),
      ),
    );
  }
}
