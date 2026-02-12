import 'package:flutter/material.dart';

import '../constants/ng_states.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';

class AdminMarketplaceScreen extends StatefulWidget {
  const AdminMarketplaceScreen({super.key});

  @override
  State<AdminMarketplaceScreen> createState() => _AdminMarketplaceScreenState();
}

class _AdminMarketplaceScreenState extends State<AdminMarketplaceScreen> {
  final _qCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String _state = allNigeriaLabel;
  String _status = 'all';
  String _sort = 'newest';
  String _category = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{
        'limit': '100',
        'sort': _sort,
      };
      if (_qCtrl.text.trim().isNotEmpty) query['q'] = _qCtrl.text.trim();
      if (_state != allNigeriaLabel) query['state'] = _state;
      if (_status != 'all') query['status'] = _status;
      if (_category.trim().isNotEmpty) query['category'] = _category.trim();
      final uri = Uri(path: '/admin/listings/search', queryParameters: query);
      final data =
          await ApiClient.instance.getJson(ApiConfig.api(uri.toString()));
      if (!mounted) return;
      final rows = (data is Map && data['items'] is List)
          ? data['items'] as List
          : <dynamic>[];
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
        _error = 'Failed to load admin marketplace: $e';
      });
    }
  }

  void _showDetails(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text((item['title'] ?? 'Listing').toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Listing ID: ${(item['id'] ?? '').toString()}'),
              Text('Price: ${formatNaira(item['price'])}'),
              Text('State: ${(item['state'] ?? '').toString()}'),
              Text('City: ${(item['city'] ?? '').toString()}'),
              Text('Category: ${(item['category'] ?? '').toString()}'),
              Text('Status: ${(item['status'] ?? '').toString()}'),
              const SizedBox(height: 8),
              const Text('Seller',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text('ID: ${(item['merchant_id'] ?? '').toString()}'),
              Text(
                  'Name: ${(item['merchant'] is Map ? item['merchant']['name'] : '').toString()}'),
              Text(
                  'Email: ${(item['merchant'] is Map ? item['merchant']['email'] : '').toString()}'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Admin Marketplace',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _qCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Search listings or merchant',
                  ),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('All Status')),
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'inactive', child: Text('Inactive')),
                        ],
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), labelText: 'Status'),
                        onChanged: (v) => setState(() => _status = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _sort,
                        items: const [
                          DropdownMenuItem(
                              value: 'newest', child: Text('Newest')),
                          DropdownMenuItem(
                              value: 'price_asc',
                              child: Text('Price Low to High')),
                          DropdownMenuItem(
                              value: 'price_desc',
                              child: Text('Price High to Low')),
                        ],
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), labelText: 'Sort'),
                        onChanged: (v) => setState(() => _sort = v ?? 'newest'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _state,
                        isExpanded: true,
                        items: <String>[allNigeriaLabel, ...nigeriaStates]
                            .map((state) => DropdownMenuItem(
                                  value: state,
                                  child: Text(state == allNigeriaLabel
                                      ? state
                                      : displayState(state)),
                                ))
                            .toList(),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(), labelText: 'State'),
                        onChanged: (v) =>
                            setState(() => _state = v ?? allNigeriaLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Category',
                        ),
                        onChanged: (v) => _category = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                        onPressed: _load, child: const Text('Apply')),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FTLoadStateLayout(
              loading: _loading,
              error: _error,
              onRetry: _load,
              empty: _items.isEmpty,
              loadingState: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  FTListCardSkeleton(),
                  SizedBox(height: 10),
                  FTListCardSkeleton(),
                  SizedBox(height: 10),
                  FTListCardSkeleton(),
                ],
              ),
              emptyState: const FTEmptyState(
                icon: Icons.storefront_outlined,
                title: 'No listings found',
                subtitle: 'Adjust search text or filters and try again.',
              ),
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = _items[index];
                  final title = (item['title'] ?? 'Listing').toString();
                  final merchantName = (item['merchant'] is Map)
                      ? (item['merchant']['name'] ?? '').toString()
                      : '';
                  final state = (item['state'] ?? '').toString();
                  final city = (item['city'] ?? '').toString();
                  final location = [city, state]
                      .where((value) => value.trim().isNotEmpty)
                      .join(', ');
                  final price = formatNaira(item['price']);
                  return ListTile(
                    title: Text(title),
                    subtitle: Text(
                      '$price • ${location.isEmpty ? "Location not set" : location}\nSeller: $merchantName',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.open_in_new_outlined),
                    onTap: () => _showDetails(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
