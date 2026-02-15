import 'package:flutter/material.dart';
import '../utils/unavailable_action.dart';

class AdminBondingScreen extends StatelessWidget {
  const AdminBondingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Inspector Bonds")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.errorContainer,
            child: ListTile(
              title: Text(
                "Underfunded Inspectors",
                style:
                    TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.bold),
              ),
              trailing: Icon(Icons.priority_high, color: scheme.onErrorContainer),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const CircleAvatar(child: Text("JD")),
            title: const Text("John Doe"),
            subtitle: const Text("Bond Balance: NGN 2,000 (Min: NGN 50,000)"),
            trailing:
                ElevatedButton(onPressed: null, child: const Text("SUSPEND")),
          ),
          const UnavailableActionHint(
            reason: 'Inspector bond suspension actions are disabled in this release.',
          ),
        ],
      ),
    );
  }
}
