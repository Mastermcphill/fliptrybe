import 'package:flutter/material.dart';
import '../utils/unavailable_action.dart';

class AdminDisputeScreen extends StatefulWidget {
  const AdminDisputeScreen({super.key});
  @override
  State<AdminDisputeScreen> createState() => _AdminDisputeScreenState();
}

class _AdminDisputeScreenState extends State<AdminDisputeScreen> {
  // In production, fetch real disputes. Mocking structure for UI build:
  final List<Map<String, dynamic>> _disputes = [
    {
      "id": 101,
      "order_id": 505,
      "reason": "Item is a fake replica",
      "evidence": "https://via.placeholder.com/600x300",
      "inspector": "Agent 007",
      "status": "FRAUD"
    }
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text("Dispute Resolution")),
      body: ListView.builder(
        itemCount: _disputes.length,
        itemBuilder: (_, i) {
          final d = _disputes[i];
          return Card(
            margin: const EdgeInsets.all(10),
            child: Column(
              children: [
                Container(
                  height: 200,
                  width: double.infinity,
                  color: scheme.surfaceContainerHighest,
                  child: Image.network(
                    d['evidence'],
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                  ),
                ),
                ListTile(
                  title: Text("Order #${d['order_id']} - ${d['status']}"),
                  subtitle: Text(d['reason']),
                  trailing: Icon(Icons.warning, color: scheme.error),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.errorContainer,
                          foregroundColor: scheme.onErrorContainer,
                        ),
                        child: const Text("UPHOLD (Refund Buyer)"),
                      ),
                      ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                        ),
                        child: const Text("OVERTURN (Pay Seller)"),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: UnavailableActionHint(
                    reason:
                        'Dispute resolution actions are disabled in this release.',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
