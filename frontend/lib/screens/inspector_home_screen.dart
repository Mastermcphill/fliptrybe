import 'package:flutter/material.dart';

import '../services/inspector_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import 'inspector_bookings_screen.dart';
import 'moneybox_dashboard_screen.dart';
import 'support_chat_screen.dart';

class InspectorHomeScreen extends StatefulWidget {
  const InspectorHomeScreen({super.key});

  @override
  State<InspectorHomeScreen> createState() => _InspectorHomeScreenState();
}

class _InspectorHomeScreenState extends State<InspectorHomeScreen> {
  final _walletService = WalletService();
  final _moneyboxService = MoneyBoxService();
  final _inspectorService = InspectorService();
  bool _loading = true;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic> _moneybox = const {};
  List<dynamic> _assignments = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _walletService.getWallet(),
        _moneyboxService.status(),
        _inspectorService.assignments(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = values[0] as Map<String, dynamic>?;
        _moneybox = values[1] as Map<String, dynamic>;
        _assignments = values[2] as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _money(dynamic value) {
    final parsed = double.tryParse((value ?? 0).toString()) ?? 0;
    return parsed.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Home'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Inspector Snapshot',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(
                            'Available Balance: NGN ${_money(_wallet?['balance'])}'),
                        Text(
                            'MoneyBox Locked: NGN ${_money(_moneybox['principal_balance'])}'),
                        Text('Pending Bookings: ${_assignments.length}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Earnings Rules',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text(
                            'Inspection payout is inspection fee minus 10% platform commission.'),
                        Text('Withdraw fee: instant 1%, standard 0%.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const InspectorBookingsScreen()),
                    );
                  },
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Bookings'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MoneyBoxDashboardScreen()),
                    );
                  },
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('MoneyBox'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SupportChatScreen()),
                    );
                  },
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Chat Admin'),
                ),
              ],
            ),
    );
  }
}
