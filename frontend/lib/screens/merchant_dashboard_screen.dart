import 'package:flutter/material.dart';

import '../services/kpi_service.dart';
import 'merchant_orders_screen.dart';
import 'merchant_kpi_trends_screen.dart';
import 'moneybox_dashboard_screen.dart';
import '../utils/auth_navigation.dart';

class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  State<MerchantDashboardScreen> createState() =>
      _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  final _kpi = KpiService();
  late Future<Map<String, dynamic>> _data;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _data = _kpi.merchantKpis();
  }

  void _reload() => setState(() => _data = _kpi.merchantKpis());

  Future<bool> _confirmSignOut() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleSignOut() async {
    if (_signingOut) return;
    final confirmed = await _confirmSignOut();
    if (!confirmed) return;

    setState(() => _signingOut = true);
    try {
      await logoutToLanding(context);
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  Widget _statCard(String label, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Dashboard'),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          TextButton(
            onPressed: _signingOut ? null : _handleSignOut,
            child: Text(
              _signingOut ? 'Signing out...' : 'Sign out',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final kpis = (snap.data?['kpis'] as Map?) ?? {};
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('KPIs',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _statCard('Total Orders', '${kpis['total_orders'] ?? 0}'),
                  const SizedBox(width: 8),
                  _statCard('Completed', '${kpis['completed_orders'] ?? 0}'),
                ],
              ),
              Row(
                children: [
                  _statCard(
                      'Gross Revenue', 'NGN ${kpis['gross_revenue'] ?? 0}'),
                  const SizedBox(width: 8),
                  _statCard(
                      'Platform Fees', 'NGN ${kpis['platform_fees'] ?? 0}'),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.list_alt_outlined),
                  title: const Text('View Orders'),
                  subtitle: const Text('Accept, assign driver, track timeline'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MerchantOrdersScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: const Text('MoneyBox'),
                  subtitle: const Text('Save from commissions'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MoneyBoxDashboardScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MerchantKpiTrendsScreen()));
                },
                icon: const Icon(Icons.insights_outlined),
                label: const Text('KPI Trends'),
              ),
            ],
          );
        },
      ),
    );
  }
}
