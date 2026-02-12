import 'package:flutter/material.dart';

import '../services/listing_service.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';
import 'not_available_yet_screen.dart';

class MerchantListingsScreen extends StatefulWidget {
  const MerchantListingsScreen({super.key});

  @override
  State<MerchantListingsScreen> createState() => _MerchantListingsScreenState();
}

class _MerchantListingsScreenState extends State<MerchantListingsScreen> {
  final ListingService _listingService = ListingService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _listingService.listMyListings();
    if (!mounted) return;
    setState(() {
      _items = rows
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      _loading = false;
    });
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
        builder: (_) => NotAvailableYetScreen(
          title: title,
          reason: reason,
        ),
      ),
    );
  }

  String _priceText(Map<String, dynamic> item) {
    final value = double.tryParse((item['price'] ?? 0).toString()) ?? 0;
    return '₦${value.toStringAsFixed(2)}';
  }

  String _statusText(Map<String, dynamic> item) {
    final activeRaw = item['is_active'];
    final isActive = activeRaw == true ||
        (activeRaw?.toString().toLowerCase() == 'true') ||
        (activeRaw?.toString() == '1');
    return isActive ? 'Active' : 'Paused';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_business_outlined),
            tooltip: 'Create listing',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Create Listing'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.inventory_2_outlined, size: 44),
                        const SizedBox(height: 12),
                        const Text(
                          'No listings yet. Create your first listing to start receiving orders.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _openCreate,
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Create Listing'),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                      itemCount: _items.length,
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        final title =
                            (item['title'] ?? 'Untitled listing').toString();
                        final description =
                            (item['description'] ?? '').toString();
                        final listingId =
                            int.tryParse((item['id'] ?? '').toString()) ?? 0;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            onTap: listingId > 0
                                ? () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ListingDetailScreen(
                                          listing:
                                              Map<String, dynamic>.from(item),
                                        ),
                                      ),
                                    )
                                : null,
                            title: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(_priceText(item)),
                                Text('Status: ${_statusText(item)}'),
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
                                      onPressed: () => _showUnavailable(
                                        'Edit Listing',
                                        'Listing edit controls are not enabled yet. You can open the listing details for now.',
                                      ),
                                      child: const Text('Edit'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _showUnavailable(
                                        'Pause / Resume Listing',
                                        'Pause and resume controls are not enabled yet.',
                                      ),
                                      child: const Text('Pause / Resume'),
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
