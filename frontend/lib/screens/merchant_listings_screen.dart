import 'package:flutter/material.dart';

import '../services/listing_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';
import 'not_available_yet_screen.dart';

class MerchantListingsScreen extends StatefulWidget {
  const MerchantListingsScreen({super.key});

  @override
  State<MerchantListingsScreen> createState() => _MerchantListingsScreenState();
}

class _MerchantListingsScreenState extends State<MerchantListingsScreen>
    with SingleTickerProviderStateMixin {
  final ListingService _listingService = ListingService();
  late final TabController _tabs;

  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _listingService.listMyListings();
      if (!mounted) return;
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
        _error = 'Failed to load listings: $e';
      });
    }
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
    if (!mounted) return;
    _load();
  }

  void _showUnavailable(String title, String reason) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotAvailableYetScreen(title: title, reason: reason),
      ),
    );
  }

  int _idOf(Map<String, dynamic> item) {
    final id = item['id'];
    if (id is int) return id;
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  String _statusOf(Map<String, dynamic> item) {
    final rawStatus = (item['status'] ?? '').toString().toLowerCase();
    final isActive = item['is_active'] == true ||
        item['is_active']?.toString().toLowerCase() == 'true' ||
        item['is_active']?.toString() == '1';
    if (rawStatus.contains('sold') || rawStatus.contains('completed')) {
      return 'sold';
    }
    if (rawStatus.contains('pending') ||
        rawStatus.contains('review') ||
        rawStatus.contains('draft')) {
      return 'pending';
    }
    if (isActive) return 'active';
    return 'inactive';
  }

  List<Map<String, dynamic>> _filteredForTab() {
    final target = switch (_tabs.index) {
      0 => 'active',
      1 => 'pending',
      2 => 'sold',
      _ => 'inactive',
    };
    return _items.where((item) => _statusOf(item) == target).toList();
  }

  String _money(dynamic value) => formatNaira(value);

  @override
  Widget build(BuildContext context) {
    final rows = _filteredForTab();
    final activeCount =
        _items.where((item) => _statusOf(item) == 'active').length;
    final pendingCount =
        _items.where((item) => _statusOf(item) == 'pending').length;
    final soldCount = _items.where((item) => _statusOf(item) == 'sold').length;
    final inactiveCount =
        _items.where((item) => _statusOf(item) == 'inactive').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Inventory'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Create listing',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Pending'),
            Tab(text: 'Sold'),
            Tab(text: 'Inactive'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Create Listing'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  FTSkeleton(height: 120),
                  SizedBox(height: 10),
                  FTSkeleton(height: 120),
                  SizedBox(height: 10),
                  FTSkeleton(height: 120),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      FTErrorState(message: _error!, onRetry: _load),
                    ],
                  )
                : rows.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          FTSectionContainer(
                            title: 'Inventory Snapshot',
                            subtitle:
                                'Views and saves metrics are not available yet. Use status tabs to manage stock.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FTPill(text: 'Active: $activeCount'),
                                FTPill(text: 'Pending: $pendingCount'),
                                FTPill(text: 'Sold: $soldCount'),
                                FTPill(text: 'Inactive: $inactiveCount'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          const FTEmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'No listings in this section',
                            subtitle:
                                'Create listings to start receiving orders and grow your storefront.',
                          ),
                          const SizedBox(height: 10),
                          FTCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Listing Capacity',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Current app limits apply per merchant plan. Upgrade and verification status can increase available listing capacity.',
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        itemCount: rows.length + 1,
                        itemBuilder: (_, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FTSectionContainer(
                                title: 'Inventory Snapshot',
                                subtitle:
                                    'Views and saves metrics are not available yet.',
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FTPill(text: 'Active: $activeCount'),
                                    FTPill(text: 'Pending: $pendingCount'),
                                    FTPill(text: 'Sold: $soldCount'),
                                    FTPill(text: 'Inactive: $inactiveCount'),
                                  ],
                                ),
                              ),
                            );
                          }
                          final rowIndex = index - 1;
                          final item = rows[rowIndex];
                          final listingId = _idOf(item);
                          final title =
                              (item['title'] ?? 'Untitled listing').toString();
                          final description =
                              (item['description'] ?? '').toString();
                          final state = (item['state'] ?? '').toString();
                          final city = (item['city'] ?? '').toString();
                          final location = [city, state]
                              .where((v) => v.trim().isNotEmpty)
                              .join(', ');
                          final status = _statusOf(item);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FTPill(text: status.toUpperCase()),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_money(item['price'])),
                                  if (location.isNotEmpty) Text(location),
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: listingId <= 0
                                            ? null
                                            : () => Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ListingDetailScreen(
                                                      listing: Map<String,
                                                          dynamic>.from(item),
                                                    ),
                                                  ),
                                                ),
                                        child: const Text('View'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _showUnavailable(
                                          'Edit Listing',
                                          'Listing edit controls are not enabled yet.',
                                        ),
                                        child: const Text('Edit'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _showUnavailable(
                                          'Bulk Actions',
                                          'Deactivate/Mark sold bulk actions are not enabled yet.',
                                        ),
                                        child: const Text('Bulk Action'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
