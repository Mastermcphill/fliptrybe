import 'package:flutter/material.dart';

import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchCtrl = TextEditingController();
  String _category = 'All';

  final List<String> _categories = const [
    'All',
    'Phones',
    'Fashion',
    'Furniture',
    'Electronics',
    'Home',
    'Sports',
  ];

  final List<Map<String, dynamic>> _items = [
    {
      'id': 1001,
      'title': 'iPhone 12 128GB',
      'price': 450000,
      'condition': 'Used - Like New',
      'category': 'Phones',
      'description': 'Clean device, factory reset, battery health 92%.',
      'is_demo': true,
    },
    {
      'id': 1002,
      'title': 'Samsung Galaxy S21',
      'price': 380000,
      'condition': 'Used - Good',
      'category': 'Phones',
      'description': 'Great condition, minor scratches on frame.',
      'is_demo': true,
    },
    {
      'id': 1003,
      'title': 'Leather Sofa Set',
      'price': 250000,
      'condition': 'Used - Good',
      'category': 'Furniture',
      'description': '3-seater + 2 chairs. Pickup only.',
      'is_demo': true,
    },
    {
      'id': 1004,
      'title': 'Wooden Dining Table',
      'price': 180000,
      'condition': 'Used - Fair',
      'category': 'Furniture',
      'description': 'Solid wood with 6 chairs.',
      'is_demo': true,
    },
    {
      'id': 1005,
      'title': 'Nike Air Max',
      'price': 65000,
      'condition': 'Used - Like New',
      'category': 'Fashion',
      'description': 'Size 42, worn twice.',
      'is_demo': true,
    },
    {
      'id': 1006,
      'title': 'Designer Handbag',
      'price': 120000,
      'condition': 'Used - Like New',
      'category': 'Fashion',
      'description': 'Comes with dust bag and receipt.',
      'is_demo': true,
    },
    {
      'id': 1007,
      'title': 'LG 55" Smart TV',
      'price': 320000,
      'condition': 'Used - Good',
      'category': 'Electronics',
      'description': '4K UHD with HDR. Remote included.',
      'is_demo': true,
    },
    {
      'id': 1008,
      'title': 'PlayStation 5',
      'price': 520000,
      'condition': 'Used - Like New',
      'category': 'Electronics',
      'description': '1 controller + 2 games.',
      'is_demo': true,
    },
    {
      'id': 1009,
      'title': 'Blender + Toaster Set',
      'price': 35000,
      'condition': 'Used - Good',
      'category': 'Home',
      'description': 'Both in working condition.',
      'is_demo': true,
    },
    {
      'id': 1010,
      'title': 'Mountain Bike',
      'price': 95000,
      'condition': 'Used - Good',
      'category': 'Sports',
      'description': '26-inch wheels, recently serviced.',
      'is_demo': true,
    },
  ];

  List<Map<String, dynamic>> _filteredItems() {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((item) {
      final title = item['title']?.toString().toLowerCase() ?? '';
      final condition = item['condition']?.toString().toLowerCase() ?? '';
      final category = item['category']?.toString() ?? '';
      final matchesCategory = _category == 'All' || _category == category;
      final matchesQuery = q.isEmpty || title.contains(q) || condition.contains(q);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  Widget _buildImageCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, size: 36, color: Color(0xFF94A3B8)),
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('Sell Item'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Flip Trybe Market',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search items',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Filters coming soon')),
                      );
                    },
                    icon: const Icon(Icons.tune),
                  )
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    return ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _categories.length,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: GridView.builder(
                  itemCount: items.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final title = item['title']?.toString() ?? '';
                    final price = item['price'] ?? 0;
                    final condition = item['condition']?.toString() ?? '';
                    final id = item['id'];

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ListingDetailScreen(listing: Map<String, dynamic>.from(item)),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _buildImageCard()),
                              const SizedBox(height: 8),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₦${price.toString()}',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                condition,
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
