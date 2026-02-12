import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';

class SalesAnalyticsScreen extends StatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  State<SalesAnalyticsScreen> createState() => _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends State<SalesAnalyticsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

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
      final data = await ApiClient.instance.getJson(ApiConfig.api('/merchant/analytics'));
      if (!mounted) return;
      setState(() {
        _data = (data is Map) ? Map<String, dynamic>.from(data) : const {};
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

  int _asInt(dynamic v) {
    try {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.parse(v.toString());
    } catch (_) {
      return 0;
    }
  }

  double _asDouble(dynamic v) {
    try {
      if (v is num) return v.toDouble();
      return double.parse(v.toString());
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final paid7 = _asInt(_data['paid_last_7']);
    final paid30 = _asInt(_data['paid_last_30']);
    final recent = (_data['recent_paid'] is List) ? (_data['recent_paid'] as List) : const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Analytics'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _statCard('Paid Orders (7d)', '$paid7'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _statCard('Paid Orders (30d)', '$paid30'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('Recent Paid Events', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    if (recent.isEmpty)
                      const Text('No recent paid events yet.')
                    else
                      ...recent.map((raw) {
                        if (raw is! Map) return const SizedBox.shrink();
                        final m = Map<String, dynamic>.from(raw);
                        final orderId = m['order_id'];
                        final amount = _asDouble(m['amount']);
                        final status = (m['status'] ?? '').toString();
                        final createdAt = (m['created_at'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text('Order #$orderId', style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(status.isEmpty ? 'paid' : status),
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('NGN ${amount.toStringAsFixed(0)}'),
                                if (createdAt.isNotEmpty)
                                  Text(createdAt, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }
}
