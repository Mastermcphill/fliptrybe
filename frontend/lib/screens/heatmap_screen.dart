import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _buckets = const [];

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
      final data = await ApiClient.instance.getJson(ApiConfig.api('/heat'));
      final buckets =
          (data['buckets'] is List) ? data['buckets'] as List : const [];
      setState(() {
        _buckets = buckets;
        _loading = false;
      });
    } catch (e) {
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
        title: const Text('Market Heat'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _buckets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = _buckets[i];
                    if (m is! Map) return const SizedBox.shrink();
                    final state = (m['state'] ?? '').toString();
                    final city = (m['city'] ?? '').toString();
                    final count = (m['count'] ?? 0).toString();
                    return ListTile(
                      leading: const Icon(Icons.local_fire_department_outlined),
                      title: Text('$state • $city'),
                      subtitle: Text('Listings: $count'),
                    );
                  },
                ),
    );
  }
}
