import 'package:flutter/material.dart';

import 'topup_screen.dart';

import '../services/wallet_service.dart';
import 'merchant_withdraw_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _svc = WalletService();
  bool _loading = true;

  Map<String, dynamic>? _wallet;
  List<dynamic> _ledger = const [];
  final _topupCtrl = TextEditingController(text: "5000");

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final w = await _svc.getWallet();
    final l = await _svc.ledger();
    setState(() {
      _wallet = w;
      _ledger = l;
      _loading = false;
    });
  }

  Future<void> _topup() async {
    final amt = double.tryParse(_topupCtrl.text.trim()) ?? 0;
    if (amt <= 0) return;
    await _svc.demoTopup(amt);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Demo topup credited ✅")));
    _load();
  }

  @override
  void dispose() {
    _topupCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bal = _wallet?['balance'] ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Wallet"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MerchantWithdrawScreen()));
              if (!mounted) return;
              _load();
            },
            icon: const Icon(Icons.outbond_outlined),
            tooltip: 'Withdraw',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Balance", style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text("₦$bal", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _topupCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Demo topup amount", border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
              onPressed: () async {
                final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const TopupScreen()));
                if (ok == true) {
                  // ignore: use_build_context_synchronously
                  Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Top Up Wallet'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                          onPressed: _topup,
                          icon: const Icon(Icons.add),
                          label: const Text("Demo Topup"),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text("Ledger", style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_ledger.isEmpty)
                  const Text("No transactions yet.")
                else
                  ..._ledger.whereType<Map>().map((raw) {
                    final m = Map<String, dynamic>.from(raw);
                    final dir = (m['direction'] ?? '').toString();
                    final amt = (m['amount'] ?? 0).toString();
                    final kind = (m['kind'] ?? '').toString();
                    final note = (m['note'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        title: Text("$dir ₦$amt", style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text("$kind\n$note"),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
