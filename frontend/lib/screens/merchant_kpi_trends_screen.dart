import 'package:flutter/material.dart';

import '../services/merchant_service.dart';

class MerchantKpiTrendsScreen extends StatefulWidget {
  const MerchantKpiTrendsScreen({super.key});

  @override
  State<MerchantKpiTrendsScreen> createState() =>
      _MerchantKpiTrendsScreenState();
}

class _MerchantKpiTrendsScreenState extends State<MerchantKpiTrendsScreen> {
  final _svc = MerchantService();
  bool _loading = true;
  Map<String, dynamic>? _kpis;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _svc.getKpis();
    if (!mounted) return;
    setState(() {
      _kpis = (data['kpis'] is Map)
          ? Map<String, dynamic>.from(data['kpis'] as Map)
          : null;
      _loading = false;
    });
  }

  Widget _bar(String label, double value, double max) {
    final pct = (max <= 0) ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(12)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct,
                child: Container(
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
              width: 70,
              child:
                  Text(value.toStringAsFixed(0), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant KPI Trends'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_kpis == null)
              ? const Center(child: Text('No KPI data.'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quick visual health snapshot',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Builder(builder: (_) {
                        final listings = (double.tryParse(
                                (_kpis?['listings_count'] ?? '0').toString()) ??
                            0);
                        final orders = (double.tryParse(
                                (_kpis?['orders_count'] ?? '0').toString()) ??
                            0);
                        final revenue = (double.tryParse(
                                (_kpis?['revenue_gross'] ?? '0').toString()) ??
                            0);
                        final commission = (double.tryParse(
                                (_kpis?['commission_total'] ?? '0')
                                    .toString()) ??
                            0);
                        final max = [listings, orders, revenue, commission]
                            .fold<double>(0, (a, b) => b > a ? b : a);
                        return Column(
                          children: [
                            _bar('Listings', listings, max),
                            _bar('Orders', orders, max),
                            _bar('Revenue', revenue, max),
                            _bar('Commission', commission, max),
                          ],
                        );
                      }),
                      const SizedBox(height: 10),
                      const Text(
                          'Tip: more completed orders = higher score + ranking.',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
    );
  }
}
