import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/order_service.dart';
import '../services/api_service.dart';

class InvestorMetricsScreen extends StatefulWidget {
  const InvestorMetricsScreen({super.key});

  @override
  State<InvestorMetricsScreen> createState() => _InvestorMetricsScreenState();
}

class _InvestorMetricsScreenState extends State<InvestorMetricsScreen> {
  final _admin = AdminService();
  final _orders = OrderService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _overview;
  int _myOrders = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = await ApiService.getProfile();
      final uid = me['id'];
      final o = await _admin.overview();
      final my =
          (uid is int) ? await _orders.myOrders(userId: uid) : <dynamic>[];
      if (!mounted) return;
      setState(() {
        _overview = o;
        _myOrders = my.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _overview?['counts'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Investor Metrics"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      "Demo KPIs (Live backend data)",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text("Total users"),
                      trailing: Text("${counts?['users'] ?? 0}"),
                    ),
                    ListTile(
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: const Text("Total listings"),
                      trailing: Text("${counts?['listings'] ?? 0}"),
                    ),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text("My orders (buyer)"),
                      trailing: Text("$_myOrders"),
                    ),
                    const Divider(height: 28),
                    const Text(
                      "Pitch line",
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "FlipTrybe is Nigeria’s trust-first marketplace engine with delivery workflows, merchant ranking, and commission-only monetization.",
                    ),
                  ],
                ),
    );
  }
}
