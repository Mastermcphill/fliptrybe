import 'package:flutter/material.dart';

import '../services/inspector_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import 'inspector_bookings_screen.dart';
import 'moneybox_dashboard_screen.dart';
import 'not_available_yet_screen.dart';
import 'support_chat_screen.dart';

class InspectorHomeScreen extends StatefulWidget {
  const InspectorHomeScreen({super.key, this.onSelectTab});

  final ValueChanged<int>? onSelectTab;

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
    final pending = _assignments.whereType<Map>().where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'assigned' || status == 'pending';
    }).length;
    final completed = _assignments.whereType<Map>().where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'completed' || status == 'submitted';
    }).length;
    final rating = _assignments.whereType<Map>().fold<double>(0.0, (sum, a) {
      final raw = double.tryParse((a['rating'] ?? 0).toString()) ?? 0;
      return sum + raw;
    });
    final ratedCount = _assignments.whereType<Map>().where((a) {
      final raw = double.tryParse((a['rating'] ?? 0).toString()) ?? 0;
      return raw > 0;
    }).length;
    final avgRating =
        ratedCount == 0 ? '-' : (rating / ratedCount).toStringAsFixed(1);
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
                        Text('Pending Bookings: $pending'),
                        Text('Completed Inspections: $completed'),
                        Text('Rating Snapshot: $avgRating'),
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
                    if (widget.onSelectTab != null) {
                      widget.onSelectTab!(1);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InspectorBookingsScreen()),
                      );
                    }
                  },
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('View Bookings'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotAvailableYetScreen(
                          title: 'Update Availability',
                          reason:
                              'Inspector availability updates are not enabled yet in this release.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.power_settings_new_outlined),
                  label: const Text('Update Availability'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    if (widget.onSelectTab != null) {
                      widget.onSelectTab!(3);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MoneyBoxDashboardScreen()),
                      );
                    }
                  },
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('MoneyBox'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    if (widget.onSelectTab != null) {
                      widget.onSelectTab!(4);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SupportChatScreen()),
                      );
                    }
                  },
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Chat Admin'),
                ),
              ],
            ),
    );
  }
}
