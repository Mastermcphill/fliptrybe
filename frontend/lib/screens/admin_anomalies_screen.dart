import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import 'admin_order_timeline_screen.dart';

class AdminAnomaliesScreen extends StatefulWidget {
  const AdminAnomaliesScreen({super.key});

  @override
  State<AdminAnomaliesScreen> createState() => _AdminAnomaliesScreenState();
}

class _AdminAnomaliesScreenState extends State<AdminAnomaliesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final data = await ApiClient.instance.getJson(ApiConfig.api('/admin/anomalies'));
      if (!mounted) return;
      final rows = (data is Map && data['items'] is List) ? data['items'] as List : <dynamic>[];
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load anomalies: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Admin Anomalies',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _items.isEmpty,
        loadingState: const Center(child: CircularProgressIndicator()),
        emptyState: const FTEmptyState(
          icon: Icons.rule_folder_outlined,
          title: 'No anomalies',
          subtitle: 'No drift or processing anomalies detected right now.',
        ),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final row = _items[index];
            final type = (row['type'] ?? '').toString();
            final orderId = int.tryParse('${row['order_id'] ?? ''}');
            return FTCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(type, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(row.toString()),
                trailing: orderId != null ? const Icon(Icons.open_in_new_outlined) : null,
                onTap: orderId == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminOrderTimelineScreen(orderId: orderId),
                          ),
                        );
                      },
              ),
            );
          },
        ),
      ),
    );
  }
}
