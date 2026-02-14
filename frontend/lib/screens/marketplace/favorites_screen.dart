import 'package:flutter/material.dart';

import '../../services/marketplace_catalog_service.dart';
import '../../services/marketplace_prefs_service.dart';
import '../../ui/components/ft_components.dart';
import '../../widgets/listing/listing_card.dart';
import '../listing_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _prefs = MarketplacePrefsService();
  final _catalog = MarketplaceCatalogService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  Set<int> _favorites = <int>{};

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
      final values = await Future.wait([
        _catalog.listAll(),
        _prefs.loadFavorites(),
      ]);
      if (!mounted) return;
      final all = values[0] as List<Map<String, dynamic>>;
      final fav = values[1] as Set<int>;
      setState(() {
        _favorites = fav;
        _items = all.where((item) => fav.contains(item['id'])).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load favorites: $e';
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> item) async {
    final id = item['id'] as int;
    final next = <int>{..._favorites};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    await _prefs.saveFavorites(next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Favorites',
      child: _loading
          ? GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.64,
              ),
              itemBuilder: (_, __) => const FTCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: FTSkeleton(height: double.infinity)),
                    SizedBox(height: 8),
                    FTSkeleton(height: 14, width: 90),
                    SizedBox(height: 6),
                    FTSkeleton(height: 12, width: 120),
                  ],
                ),
              ),
            )
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const FTEmptyState(
                      icon: Icons.favorite_border,
                      title: 'No favorites yet',
                      subtitle:
                          'Tap the heart icon on any listing card to build your watchlist.',
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.64,
                      ),
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        return ListingCard(
                          item: item,
                          isFavorite: _favorites.contains(item['id']),
                          onToggleFavorite: () => _toggle(item),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ListingDetailScreen(listing: item),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
