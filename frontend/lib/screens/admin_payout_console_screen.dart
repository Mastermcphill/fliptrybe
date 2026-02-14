import 'package:flutter/material.dart';

import '../services/admin_wallet_service.dart';

class AdminPayoutConsoleScreen extends StatefulWidget {
  const AdminPayoutConsoleScreen({super.key});

  @override
  State<AdminPayoutConsoleScreen> createState() =>
      _AdminPayoutConsoleScreenState();
}

class _AdminPayoutConsoleScreenState extends State<AdminPayoutConsoleScreen> {
  final _svc = AdminWalletService();
  String _status = "pending";
  bool _loading = true;
  List<dynamic> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.listPayouts(status: _status);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _approve(int id) async {
    final ok = await _svc.approve(id);
    _toast(ok ? "Approved ✅" : "Approve failed");
    _load();
  }

  Future<void> _reject(int id) async {
    final ok = await _svc.reject(id);
    _toast(ok ? "Rejected ✅" : "Reject failed");
    _load();
  }

  Future<void> _pay(int id) async {
    final ok = await _svc.pay(id);
    _toast(ok ? "Paid via provider ✅" : "Provider pay failed");
    _load();
  }

  Future<void> _markPaid(int id) async {
    final ok = await _svc.markPaid(id);
    _toast(ok ? "Marked paid ✅" : "Mark paid failed");
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin: Payout Console"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), labelText: "Status"),
              items: const [
                DropdownMenuItem(value: "pending", child: Text("pending")),
                DropdownMenuItem(value: "approved", child: Text("approved")),
                DropdownMenuItem(value: "paid", child: Text("paid")),
                DropdownMenuItem(value: "rejected", child: Text("rejected")),
              ],
              onChanged: (v) {
                setState(() => _status = v ?? "pending");
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_rows.isEmpty)
                    ? const Center(child: Text("No payouts."))
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final raw = _rows[i];
                          if (raw is! Map) return const SizedBox.shrink();
                          final m = Map<String, dynamic>.from(raw);
                          final id =
                              int.tryParse((m["id"] ?? "").toString()) ?? 0;
                          final userId = m["user_id"] ?? "";
                          final amount = m["amount"] ?? 0;
                          final status = (m["status"] ?? "").toString();
                          final bank = (m["bank_name"] ?? "").toString();
                          final acct = (m["account_number"] ?? "").toString();

                          return Card(
                            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Payout #$id",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 4),
                                  Text("User: $userId   •   ₦$amount"),
                                  Text("Status: $status"),
                                  if (bank.isNotEmpty || acct.isNotEmpty)
                                    Text("Bank: $bank  $acct"),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    children: [
                                      ElevatedButton(
                                          onPressed: () => _approve(id),
                                          child: const Text("Approve")),
                                      ElevatedButton(
                                          onPressed: () => _reject(id),
                                          child: const Text("Reject")),
                                      ElevatedButton(
                                          onPressed: () async {
                                            final ok = await _svc.process(id);
                                            _toast(ok
                                                ? 'Processed ✅'
                                                : 'Process failed');
                                            _load();
                                          },
                                          child: const Text('Process')),
                                      ElevatedButton(
                                          onPressed: () => _pay(id),
                                          child: const Text("Pay (Provider)")),
                                      ElevatedButton(
                                          onPressed: () => _markPaid(id),
                                          child: const Text("Mark Paid")),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
