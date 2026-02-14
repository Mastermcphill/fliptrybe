import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import 'moneybox_tier_screen.dart';
import 'moneybox_autosave_screen.dart';
import 'moneybox_withdraw_screen.dart';
import 'moneybox_ledger_screen.dart';

class MoneyBoxDashboardScreen extends StatefulWidget {
  const MoneyBoxDashboardScreen({super.key});

  @override
  State<MoneyBoxDashboardScreen> createState() =>
      _MoneyBoxDashboardScreenState();
}

class _MoneyBoxDashboardScreenState extends State<MoneyBoxDashboardScreen> {
  final _svc = MoneyBoxService();
  late Future<Map<String, dynamic>> _status;

  @override
  void initState() {
    super.initState();
    _status = _svc.status();
  }

  void _reload() {
    setState(() => _status = _svc.status());
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MoneyBox'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _status,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data ?? {};
          final status = (data['status'] ?? 'none').toString().toLowerCase();

          if (status == 'pending_approval') {
            return const Center(
                child:
                    Text('Pending approval. MoneyBox unlocks after approval.'));
          }
          if (status == 'not_eligible') {
            return const Center(
                child: Text(
                    'MoneyBox is available to Merchants, Drivers, and Inspectors.'));
          }

          final principal = (data['principal_balance'] ?? 0).toString();
          final bonus = (data['projected_bonus'] ?? 0).toString();
          final tier = (data['tier'] ?? 1).toString();
          final autosave = (data['autosave_percent'] ?? 0).toString();
          final autoOpen = _formatDate(data['auto_open_at']?.toString());
          final maturity = _formatDate(data['maturity_at']?.toString());

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'MoneyBox helps you save from commission earnings. FlipTrybe is not a bank. FlipTrybe does not invest your money.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  title: Text('Status: ${status.toUpperCase()}'),
                  subtitle: Text('Tier $tier • Autosave $autosave%'),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  title: Text('Principal: ₦$principal'),
                  subtitle: Text('Projected bonus: ₦$bonus'),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  title: Text('Auto-open: $autoOpen'),
                  subtitle: Text('Maturity: $maturity'),
                ),
              ),
              const SizedBox(height: 14),
              if (status == 'none' || status == 'closed')
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MoneyBoxTierScreen()),
                    );
                    _reload();
                  },
                  child: const Text('Open MoneyBox'),
                ),
              if (status != 'none' && status != 'closed') ...[
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MoneyBoxAutosaveScreen()),
                    );
                    _reload();
                  },
                  child: const Text('Configure Autosave'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => MoneyBoxWithdrawScreen(status: data)),
                    );
                    _reload();
                  },
                  child: const Text('Withdraw'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MoneyBoxLedgerScreen()),
                    );
                  },
                  child: const Text('View History'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
