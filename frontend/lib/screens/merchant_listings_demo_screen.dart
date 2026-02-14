import 'package:flutter/material.dart';

import '../services/listing_service.dart';
import 'listing_detail_screen.dart';

class MerchantListingsDemoScreen extends StatefulWidget {
  const MerchantListingsDemoScreen({super.key});

  @override
  State<MerchantListingsDemoScreen> createState() =>
      _MerchantListingsDemoScreenState();
}

class _MerchantListingsDemoScreenState
    extends State<MerchantListingsDemoScreen> {
  final _svc = ListingService();
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _svc.listMyListings();
  }

  void _reload() {
    setState(() => _items = _svc.listMyListings());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text(
                  'No listings found. If you are a merchant, create one from the Sell screen.'),
            );
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final raw = items[i];
              if (raw is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(raw);
              final title = (m['title'] ?? '').toString();
              final description = (m['description'] ?? '').toString();
              final price = m['price'];
              final createdAt = (m['created_at'] ?? '').toString();
              final id = m['id'];

              final priceText =
                  (price == null) ? '' : 'Price: ${price.toString()}';
              final createdText =
                  createdAt.isEmpty ? '' : 'Created: $createdAt';
              final meta = [
                if (priceText.isNotEmpty) priceText,
                if (createdText.isNotEmpty) createdText,
              ].join('  -  ');
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ListingDetailScreen(
                            listing: Map<String, dynamic>.from(m)),
                      ),
                    );
                  },
                  title: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (description.isNotEmpty)
                        Text(description,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (meta.isNotEmpty) const SizedBox(height: 6),
                      if (meta.isNotEmpty)
                        Text(meta,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                'Delete demo: endpoint will be added in next pass.')),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
