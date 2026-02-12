import 'package:flutter/material.dart';

import '../services/merchant_service.dart';
import 'leaderboards_screen.dart';
import 'not_available_yet_screen.dart';

class MerchantGrowthScreen extends StatefulWidget {
  const MerchantGrowthScreen({super.key, this.onSelectTab});

  final ValueChanged<int>? onSelectTab;

  @override
  State<MerchantGrowthScreen> createState() => _MerchantGrowthScreenState();
}

class _MerchantGrowthScreenState extends State<MerchantGrowthScreen> {
  final _merchantService = MerchantService();
  bool _loading = true;
  List<dynamic> _leaders = const [];
  Map<String, dynamic> _kpis = const {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _merchantService.getLeaderboard(),
        _merchantService.getKpis(),
      ]);
      if (!mounted) return;
      setState(() {
        _leaders = values[0] as List<dynamic>;
        _kpis = values[1] as Map<String, dynamic>;
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

  int _topRank() {
    if (_leaders.isEmpty) return 0;
    final raw = _leaders.first;
    if (raw is! Map) return 0;
    return int.tryParse((raw['rank'] ?? '0').toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final totalOrders =
        int.tryParse((_kpis['total_orders'] ?? 0).toString()) ?? 0;
    final completed =
        int.tryParse((_kpis['completed_orders'] ?? 0).toString()) ?? 0;
    final grossRevenue = _money(_kpis['gross_revenue']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Growth'),
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
                        const Text('Growth Snapshot',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Total Orders: $totalOrders'),
                        Text('Completed Orders: $completed'),
                        Text('Gross Revenue: ₦$grossRevenue'),
                        Text(
                            'Top leaderboard rank: ${_topRank() > 0 ? '#${_topRank()}' : 'Unranked'}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text('Top-Tier Incentive',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text('Buyer pays: base price + platform fee.'),
                        Text('Merchant receives base price.'),
                        Text(
                            'Top-tier merchants receive 11/13 of the platform fee.'),
                        Text('Platform keeps 2/13 of the platform fee.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const LeaderboardsScreen()),
                    );
                  },
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Open Leaderboards'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotAvailableYetScreen(
                          title: 'Followers',
                          reason:
                              'Followers detail view is not enabled yet. Use rankings for growth tracking.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.people_alt_outlined),
                  label: const Text('Followers'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => widget.onSelectTab?.call(0),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Back to Home tab'),
                ),
              ],
            ),
    );
  }
}
