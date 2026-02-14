import 'package:flutter/material.dart';

import '../services/wallet_service.dart';

class MerchantEarningsScreen extends StatefulWidget {
  const MerchantEarningsScreen({super.key});

  @override
  State<MerchantEarningsScreen> createState() => _MerchantEarningsScreenState();
}

class _MerchantEarningsScreenState extends State<MerchantEarningsScreen> {
  final _svc = WalletService();
  bool _loading = true;
  List<dynamic> _txns = const [];
  double _total = 0.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txns = await _svc.getTxns();
    double total = 0.0;
    final filtered = <dynamic>[];
    for (final t in txns) {
      if (t is! Map) continue;
      final m = Map<String, dynamic>.from(t as Map);
      final kind = (m["kind"] ?? "").toString();
      if (kind == "order_sale") {
        filtered.add(m);
        total += (double.tryParse((m["amount"] ?? "0").toString()) ?? 0.0);
      }
    }
    if (!mounted) return;
    setState(() {
      _txns = filtered;
      _total = total;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Merchant Earnings"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Card(
                    child: ListTile(
                      title: const Text("Total Sales Earnings",
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      trailing: Text("₦${_total.toStringAsFixed(2)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                  ),
                ),
                Expanded(
                  child: _txns.isEmpty
                      ? const Center(
                          child: Text(
                              "No earnings yet. Complete an order to see wallet credits."))
                      : ListView.builder(
                          itemCount: _txns.length,
                          itemBuilder: (_, i) {
                            final m =
                                Map<String, dynamic>.from(_txns[i] as Map);
                            final ref = (m["reference"] ?? "").toString();
                            final amt = (m["amount"] ?? 0).toString();
                            final note = (m["note"] ?? "").toString();
                            return Card(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              child: ListTile(
                                title: Text("₦$amt",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900)),
                                subtitle: Text("$ref\n$note"),
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
