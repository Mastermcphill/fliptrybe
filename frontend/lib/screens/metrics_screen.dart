import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../utils/formatters.dart';

class MetricsScreen extends StatefulWidget {
  const MetricsScreen({super.key});

  @override
  State<MetricsScreen> createState() => _MetricsScreenState();
}

class _MetricsScreenState extends State<MetricsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final data =
          await ApiClient.instance.getJson(ApiConfig.api('/investor/analytics'));
      if (data is! Map || data['ok'] != true) {
        throw Exception((data is Map ? data['message'] : null) ??
            'Failed to load investor analytics.');
      }
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(data);
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
    final int commissionMinor =
        int.tryParse('${_data?['commission_revenue_minor'] ?? 0}') ?? 0;
    final Map<String, dynamic> unitEconomics = _data?['unit_economics'] is Map
        ? Map<String, dynamic>.from(_data?['unit_economics'] as Map)
        : const <String, dynamic>{};
    final int avgCommissionMinor =
        int.tryParse('${unitEconomics['avg_commission_per_order_minor'] ?? 0}') ??
            0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Investor Metrics'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 40),
                    const Icon(Icons.query_stats_outlined, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: const Text('Retry')),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Mode: investor_analytics',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Active users (30d): ${_data?['active_users_last_30_days'] ?? 0}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text(
                      'Trend points: ${(_data?['gmv_trend'] as List?)?.length ?? 0}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Divider(height: 28),
                    Text(
                      'Commission Revenue: ${formatNaira(commissionMinor / 100)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Avg Commission/Order: ${formatNaira(avgCommissionMinor / 100)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
    );
  }
}
