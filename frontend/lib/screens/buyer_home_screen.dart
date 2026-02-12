import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import 'marketplace_screen.dart';
import 'orders_screen.dart';
import 'role_signup_screen.dart';
import 'support_chat_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  final _walletService = WalletService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _wallet;
  List<dynamic> _ledger = const [];

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _reload();
    } else {
      _loading = false;
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _walletService.getWallet(),
        _walletService.ledger(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = values[0] as Map<String, dynamic>?;
        _ledger = values[1] as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load wallet snapshot.';
        _loading = false;
      });
    }
  }

  String _money(dynamic value) {
    final parsed = double.tryParse((value ?? 0).toString()) ?? 0;
    return parsed.toStringAsFixed(2);
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _txRow(Map<String, dynamic> tx) {
    final amount = (tx['amount'] ?? 0).toString();
    final direction = (tx['direction'] ?? '').toString().toLowerCase();
    final kind = (tx['kind'] ?? '').toString();
    final isCredit = direction == 'credit';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isCredit ? Icons.south_west_outlined : Icons.north_east_outlined,
        color: isCredit ? Colors.green : Colors.redAccent,
      ),
      title: Text(kind.isEmpty ? 'Transaction' : kind),
      subtitle: Text(direction.isEmpty ? '-' : direction),
      trailing: Text(
        '?$amount',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txs = _ledger
        .whereType<Map>()
        .take(3)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buyer Home'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Quick Actions',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _quickAction(
                      icon: Icons.storefront_outlined,
                      label: 'Browse Marketplace',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MarketplaceScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _quickAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'My Orders',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrdersScreen()),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _quickAction(
                      icon: Icons.support_agent_outlined,
                      label: 'Chat Admin',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SupportChatScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _quickAction(
                      icon: Icons.track_changes_outlined,
                      label: 'Track Order',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrdersScreen()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('How FlipTrybe Protects You',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Secure Escrow'),
                        Text('Delivery Code + QR'),
                        Text('Optional Inspection'),
                        Text(
                            'Refund if seller does not respond within 2 hours'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('My Wallet Snapshot',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current balance: ?${_money(_wallet?['balance'])}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!,
                              style: const TextStyle(color: Colors.redAccent)),
                        ],
                        const SizedBox(height: 8),
                        if (txs.isEmpty)
                          const Text('No recent transactions.')
                        else
                          ...txs.map(_txRow),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('MoneyBox',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MoneyBox is available to Merchants, Drivers and Inspectors. Apply for a role to unlock structured savings bonuses.',
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RoleSignupScreen()),
                          ),
                          icon: const Icon(Icons.upgrade_outlined),
                          label: const Text('Apply for Role'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
