import 'package:flutter/material.dart';

import 'shortlet_screen.dart';
import 'marketplace/marketplace_search_results_screen.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  static const _categories = <String>[
    "Food & Groceries",
    "Pharmacy",
    "Electronics",
    "Fashion",
    "Beauty",
    "Home & Living",
    "Shortlets",
    "Services",
    "Transport",
    "Wholesale",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView.separated(
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (_, i) {
          final c = _categories[i];
          return ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(c),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (c == "Shortlets") {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ShortletScreen()));
                return;
              }
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          MarketplaceSearchResultsScreen(initialQuery: c)));
            },
          );
        },
      ),
    );
  }
}
