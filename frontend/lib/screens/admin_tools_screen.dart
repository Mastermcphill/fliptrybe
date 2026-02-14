import 'package:flutter/material.dart';

import 'admin_commission_rules_screen.dart';
import 'admin_payout_console_screen.dart';

class AdminToolsScreen extends StatelessWidget {
  const AdminToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Tools")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text("Payout Console",
                  style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminPayoutConsoleScreen())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.percent_outlined),
              title: const Text("Commission Rules",
                  style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AdminCommissionRulesScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
