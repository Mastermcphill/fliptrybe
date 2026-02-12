import 'package:flutter/material.dart';

import '../services/marketplace_catalog_service.dart';
import '../services/marketplace_prefs_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/theme/ft_tokens.dart';
import '../widgets/listing/listing_card.dart';
import 'create_listing_screen.dart';
import 'listing_detail_screen.dart';
import 'marketplace/favorites_screen.dart';
import 'marketplace/marketplace_search_results_screen.dart';
import 'marketplace/saved_searches_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _catalog = MarketplaceCatalogService();
  final _prefs = MarketplacePrefsService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  Set<int> _favorites = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      setState(() {
        _all = values[0] as List<Map<String, dynamic>>;
        _favorites = values[1] as Set<int>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load marketplace. Pull to retry.';
      });
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = item['id'] is int ? item['id'] as int : int.tryParse('${item['id']}') ?? -1;
    if (id <= 0) return;
    final next = <int>{..._favorites};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favorites = next);
    await _prefs.saveFavorites(next);
  }

  void _openResults({
    String query = '',
    String sort = 'relevance',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketplaceSearchResultsScreen(
          initialQuery: query,
          initialSort: sort,
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required String seeAllSort,
  }) {
    return Column(
      children: [
        FTSectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: TextButton(
            onPressed: () => _openResults(
              query: _searchCtrl.text.trim(),
              sort: seeAllSort,
            ),
            child: const Text('See all'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 280,
          child: items.isEmpty
              ? const FTCard(
                  child: Center(child: Text('No items in this section yet.')),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final id = item['id'] as int;
                    return SizedBox(
                      width: 210,
                      child: ListingCard(
                        item: item,
                        isFavorite: _favorites.contains(id),
                        onToggleFavorite: () => _toggleFavorite(item),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ListingDetailScreen(listing: item),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _catalog.recommended(_all, limit: 10);
    final trending = _catalog.trending(_all, limit: 10);
    final newest = _catalog.newest(_all, limit: 10);
    final bestValue = _catalog.bestValue(_all, limit: 10);

    return FTScaffold(
      title: 'FlipTrybe Marketplace',
      actions: [
        IconButton(
          tooltip: 'Saved searches',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SavedSearchesScreen()),
          ),
          icon: const Icon(Icons.bookmarks_outlined),
        ),
        IconButton(
          tooltip: 'Favorites',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FavoritesScreen()),
          ),
          icon: const Icon(Icons.favorite_border),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateListingScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Sell Item'),
      ),
      child: _loading
          ? const _MarketplaceSkeleton()
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        floating: true,
                        toolbarHeight: 72,
                        backgroundColor: FTTokens.bg,
                        surfaceTintColor: FTTokens.bg,
                        elevation: 0,
                        titleSpacing: 16,
                        title: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) => _openResults(query: value),
                          decoration: InputDecoration(
                            hintText: 'Search marketplace',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.tune),
                              tooltip: 'Open filters',
                              onPressed: () => _openResults(query: _searchCtrl.text),
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Column(
                            children: [
                              _section(
                                context,
                                title: 'Recommended for you',
                                subtitle: 'Based on active listings and quality score',
                                items: recommended,
                                seeAllSort: 'relevance',
                              ),
                              const SizedBox(height: 18),
                              _section(
                                context,
                                title: 'Trending near you',
                                subtitle: 'Fast-moving listings with strong demand',
                                items: trending,
                                seeAllSort: 'distance',
                              ),
                              const SizedBox(height: 18),
                              _section(
                                context,
                                title: 'Newly listed',
                                subtitle: 'Fresh listings from across Nigeria',
                                items: newest,
                                seeAllSort: 'newest',
                              ),
                              const SizedBox(height: 18),
                              _section(
                                context,
                                title: 'Best value',
                                subtitle: 'Low-price options with solid condition tags',
                                items: bestValue,
                                seeAllSort: 'price_low',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _MarketplaceSkeleton extends StatelessWidget {
  const _MarketplaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const FTSkeleton(height: 48),
        const SizedBox(height: 14),
        ...List.generate(
          3,
          (section) => Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FTSkeleton(height: 18, width: 180),
                const SizedBox(height: 8),
                const FTSkeleton(height: 12, width: 240),
                const SizedBox(height: 10),
                SizedBox(
                  height: 240,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) => const SizedBox(
                      width: 210,
                      child: FTCard(
                        padding: EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: FTSkeleton(height: double.infinity)),
                            SizedBox(height: 8),
                            FTSkeleton(height: 16, width: 100),
                            SizedBox(height: 6),
                            FTSkeleton(height: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
