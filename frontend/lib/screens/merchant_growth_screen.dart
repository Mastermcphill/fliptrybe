import 'package:flutter/material.dart';

import '../services/merchant_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import 'growth/growth_analytics_screen.dart';
import 'leaderboards_screen.dart';
import 'merchant_followers_screen.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load growth insights: $e';
        _loading = false;
      });
    }
  }

  String _money(dynamic value) => formatNaira(value);

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

    return FTScaffold(
      title: 'Merchant Growth',
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
      child: _loading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                FTSkeleton(height: 112),
                SizedBox(height: 10),
                FTSkeleton(height: 130),
                SizedBox(height: 10),
                FTSkeleton(height: 130),
              ],
            )
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _reload)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    FTSectionContainer(
                      title: 'Growth Snapshot',
                      subtitle: 'Merchant outcomes and leaderboard momentum',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total orders: $totalOrders'),
                          Text('Completed orders: $completed'),
                          Text('Gross revenue: $grossRevenue'),
                          Text(
                            'Top leaderboard rank: ${_topRank() > 0 ? '#${_topRank()}' : 'Unranked'}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const FTSectionContainer(
                      title: 'Top-Tier Incentive',
                      subtitle: 'Commission split summary',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Buyer pays: base price + platform fee.'),
                          Text('Merchant receives base price.'),
                          Text(
                              'Top-tier merchants receive 11/13 of the platform fee.'),
                          Text('Platform keeps 2/13 of the platform fee.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const GrowthAnalyticsScreen(role: 'merchant'),
                        ),
                      ),
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Estimate Earnings'),
                    ),
                    const SizedBox(height: 8),
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
                              builder: (_) => const MerchantFollowersScreen()),
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
