import 'package:flutter/material.dart';
import '../services/admin_audit_service.dart';

class AdminDisputeScreen extends StatefulWidget {
  const AdminDisputeScreen({super.key});
  @override
  State<AdminDisputeScreen> createState() => _AdminDisputeScreenState();
}

class _AdminDisputeScreenState extends State<AdminDisputeScreen> {
  final _svc = AdminAuditService();
  // In production, fetch real disputes. Mocking structure for UI build:
  final List<Map<String, dynamic>> _disputes = [
    {
      "id": 101,
      "order_id": 505,
      "reason": "Item is a fake replica",
      "evidence":
          "[https://via.placeholder.com/300](https://via.placeholder.com/300)",
      "inspector": "Agent 007",
      "status": "FRAUD"
    }
  ];

  @override
  Widget build(BuildContext context) {
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
                  color: Colors.grey.shade300,
                  child: Image.network(
                    d['evidence'],
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
                  ),
                ),
                ListTile(
                  title: Text("Order #${d['order_id']} - ${d['status']}"),
                  subtitle: Text(d['reason']),
                  trailing: const Icon(Icons.warning, color: Colors.red),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white),
                        child: const Text("UPHOLD (Refund Buyer)"),
                      ),
                      ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white),
                        child: const Text("OVERTURN (Pay Seller)"),
                      ),
                    ],
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
