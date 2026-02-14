import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

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
      final data = await ApiClient.instance.getJson(ApiConfig.api("/metrics"));
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Investor Metrics"),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
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
                    ElevatedButton(
                        onPressed: _load, child: const Text("Retry")),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text("Mode: ${_data?['mode'] ?? 'mock'}",
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    Text("Users: ${_data?['users'] ?? 0}",
                        style: const TextStyle(fontSize: 16)),
                    Text("Listings: ${_data?['listings'] ?? 0}",
                        style: const TextStyle(fontSize: 16)),
                    const Divider(height: 28),
                    Text("GMV: ₦${_data?['gmv'] ?? 0}",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                        "Total Commission: ₦${_data?['commissions_total'] ?? 0}",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
    );
  }
}
