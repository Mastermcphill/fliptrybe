import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';

class AdminOrderTimelineScreen extends StatefulWidget {
  const AdminOrderTimelineScreen({super.key, required this.orderId});

  final int orderId;

  @override
  State<AdminOrderTimelineScreen> createState() => _AdminOrderTimelineScreenState();
}

class _AdminOrderTimelineScreenState extends State<AdminOrderTimelineScreen> {
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
      final data = await ApiClient.instance
          .getJson(ApiConfig.api('/admin/orders/${widget.orderId}/timeline'));
      if (!mounted) return;
      final rows = (data is Map && data['items'] is List) ? data['items'] as List : <dynamic>[];
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load timeline: $e';
      });
    }
  }

  Color _chipColor(String kind) {
    final v = kind.toLowerCase();
    if (v.contains('payment')) return Colors.green.shade100;
    if (v.contains('escrow')) return Colors.blue.shade100;
    if (v.contains('webhook')) return Colors.orange.shade100;
    if (v.contains('ledger')) return Colors.purple.shade100;
    return Colors.grey.shade200;
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Order #${widget.orderId} Timeline',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _items.isEmpty,
        loadingState: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            FTListCardSkeleton(withImage: false),
            SizedBox(height: 10),
            FTListCardSkeleton(withImage: false),
            SizedBox(height: 10),
            FTListCardSkeleton(withImage: false),
          ],
        ),
        emptyState: const FTEmptyState(
          icon: Icons.timeline_outlined,
          title: 'No timeline events',
          subtitle: 'This order has no recorded operator events yet.',
        ),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final row = _items[index];
            final kind = (row['kind'] ?? '').toString();
            final title = (row['title'] ?? '').toString();
            final timestamp = (row['timestamp'] ?? '').toString();
            return FTCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _chipColor(kind),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(kind, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
                      const Spacer(),
                      Text(timestamp, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text((row['meta'] ?? {}).toString(), style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
