import 'package:flutter/material.dart';
import '../utils/unavailable_action.dart';

class AdminBondingScreen extends StatelessWidget {
  const AdminBondingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Inspector Bonds")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            color: Colors.redAccent,
            child: ListTile(
              title: Text(
                "Underfunded Inspectors",
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              trailing: Icon(Icons.priority_high, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          ListTile(
            leading: const CircleAvatar(child: Text("JD")),
            title: const Text("John Doe"),
            subtitle: const Text("Bond Balance: ?2,000 (Min: ?50,000)"),
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
