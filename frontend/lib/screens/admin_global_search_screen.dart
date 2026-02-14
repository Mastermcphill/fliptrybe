import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import 'admin_order_timeline_screen.dart';

class AdminGlobalSearchScreen extends StatefulWidget {
  const AdminGlobalSearchScreen({super.key});

  @override
  State<AdminGlobalSearchScreen> createState() =>
      _AdminGlobalSearchScreenState();
}

class _AdminGlobalSearchScreenState extends State<AdminGlobalSearchScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _groups = const {};

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() {
        _groups = const {};
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiClient.instance.getJson(
          ApiConfig.api('/admin/search?q=${Uri.encodeQueryComponent(q)}'));
      if (!mounted) return;
      final groups = (data is Map && data['groups'] is Map)
          ? Map<String, dynamic>.from(data['groups'] as Map)
          : <String, dynamic>{};
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Search failed: $e';
      });
    }
  }

  Widget _section(String title, List<dynamic> rows,
      Widget Function(Map<String, dynamic>) tileBuilder) {
    return FTSectionContainer(
      title: title,
      child: rows.isEmpty
          ? const Text('No matches.')
          : Column(
              children: rows
                  .whereType<Map>()
                  .map((raw) => tileBuilder(Map<String, dynamic>.from(raw)))
                  .toList(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users =
        (_groups['users'] is List) ? _groups['users'] as List : <dynamic>[];
    final orders =
        (_groups['orders'] is List) ? _groups['orders'] as List : <dynamic>[];
    final listings = (_groups['listings'] is List)
        ? _groups['listings'] as List
        : <dynamic>[];
    final intents = (_groups['payment_intents'] is List)
        ? _groups['payment_intents'] as List
        : <dynamic>[];

    return FTScaffold(
      title: 'Admin Global Search',
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _search,
        empty: false,
        loadingState: const Center(child: CircularProgressIndicator()),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _ctrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Search users, orders, listings, intents',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            _section(
              'Users',
              users,
              (row) => ListTile(
                dense: true,
                title: Text((row['email'] ?? '').toString()),
                subtitle:
                    Text('ID ${row['id']} • ${(row['role'] ?? '').toString()}'),
              ),
            ),
            const SizedBox(height: 10),
            _section(
              'Orders',
              orders,
              (row) => ListTile(
                dense: true,
                title: Text('Order #${row['id']}'),
                subtitle: Text('Status: ${(row['status'] ?? '').toString()}'),
                trailing: const Icon(Icons.timeline_outlined),
                onTap: () {
                  final id = int.tryParse('${row['id']}');
                  if (id == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminOrderTimelineScreen(orderId: id),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            _section(
              'Listings',
              listings,
              (row) => ListTile(
                dense: true,
                title: Text((row['title'] ?? '').toString()),
                subtitle: Text('Listing #${row['id']}'),
              ),
            ),
            const SizedBox(height: 10),
            _section(
              'Payment Intents',
              intents,
              (row) => ListTile(
                dense: true,
                title: Text((row['reference'] ?? '').toString()),
                subtitle: Text(
                    'Intent #${row['id']} • ${(row['status'] ?? '').toString()}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
