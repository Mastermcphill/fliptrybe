import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import 'merchant_withdraw_screen.dart';

class InspectorEarningsScreen extends StatefulWidget {
  const InspectorEarningsScreen({super.key});

  @override
  State<InspectorEarningsScreen> createState() =>
      _InspectorEarningsScreenState();
}

class _InspectorEarningsScreenState extends State<InspectorEarningsScreen> {
  final WalletService _walletService = WalletService();
  bool _loading = true;
  Map<String, dynamic>? _wallet;
  List<Map<String, dynamic>> _ledger = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final values = await Future.wait([
      _walletService.getWallet(),
      _walletService.ledger(),
    ]);
    if (!mounted) return;
    setState(() {
      _wallet = values[0] as Map<String, dynamic>?;
      _ledger = (values[1] as List<dynamic>)
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      _loading = false;
    });
  }

  String _money(dynamic value) {
    final parsed = double.tryParse((value ?? 0).toString()) ?? 0;
    return parsed.toStringAsFixed(2);
  }

  Future<void> _openWithdraw() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MerchantWithdrawScreen()),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final latest = _ledger.take(5).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Earnings'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Wallet Balance',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '?${_money(_wallet?['balance'])}',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Withdrawal Fees',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 8),
                        Text('Standard withdrawal: 0%'),
                        Text('Instant withdrawal: 1%'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openWithdraw,
                  icon: const Icon(Icons.outbond_outlined),
                  label: const Text('Withdraw'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                if (latest.isEmpty)
                  const Text('No transactions yet.')
                else
                  ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: latest.length,
                    itemBuilder: (_, index) {
                      final txn = latest[index];
                      final direction = (txn['direction'] ?? '').toString();
                      final amount = _money(txn['amount']);
                      final kind = (txn['kind'] ?? '').toString();
                      final note = (txn['note'] ?? '').toString();
                      return Card(
                        child: ListTile(
                          title: Text(
                            '$direction ?$amount',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text('$kind\n$note'),
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}
