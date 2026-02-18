import 'package:flutter/material.dart';

import '../constants/ng_cities.dart';
import '../services/marketplace_catalog_service.dart';
import '../services/city_preference_service.dart';
import '../services/marketplace_prefs_service.dart';
import '../services/auth_gate_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/design/ft_tokens.dart';
import '../utils/auth_navigation.dart';
import '../utils/ft_routes.dart';
import '../widgets/listing/listing_card.dart';
import '../utils/ui_feedback.dart';
import 'cart_screen.dart';
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
  final _cityPrefs = CityPreferenceService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _recommendedRemote = const [];
  List<Map<String, dynamic>> _dealsRemote = const [];
  List<Map<String, dynamic>> _newDropsRemote = const [];
  Set<int> _favorites = <int>{};
  String _preferredCity = defaultDiscoveryCity;
  String _preferredState = defaultDiscoveryState;

  @override
  void initState() {
    super.initState();
    _seedFromCache();
    _load(showLoading: _all.isEmpty);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _seedFromCache() {
    final cached = _catalog.cachedDiscoveryFeed();
    if (cached == null) return;
    final cachedListings = (cached['listings'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList(growable: false);
    final cachedRecommended =
        (cached['recommended'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList(growable: false);
    final cachedDeals = (cached['deals'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList(growable: false);
    final cachedDrops = (cached['new_drops'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .toList(growable: false);
    setState(() {
      _all = cachedListings;
      _recommendedRemote = cachedRecommended;
      _dealsRemote = cachedDeals;
      _newDropsRemote = cachedDrops;
      _loading = false;
      _error = null;
    });
  }

  bool get _hasRenderableData =>
      _all.isNotEmpty ||
      _recommendedRemote.isNotEmpty ||
      _dealsRemote.isNotEmpty ||
      _newDropsRemote.isNotEmpty;

  Future<void> _load({bool showLoading = true}) async {
    setState(() {
      if (showLoading) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final values = await Future.wait([
        _catalog.listAll(),
        _prefs.loadFavorites(),
        _cityPrefs.syncFromServer(),
      ]);
      final pref = Map<String, String>.from(values[2] as Map<String, String>);
      final city = (pref['preferred_city'] ?? defaultDiscoveryCity).trim();
      final state = (pref['preferred_state'] ?? defaultDiscoveryState).trim();
      final remoteRecommended = await _catalog.recommendedRemote(
        city: city,
        state: state,
        limit: 12,
      );
      final remoteDeals = await _catalog.dealsRemote(
        city: city,
        state: state,
        limit: 12,
      );
      final remoteDrops = await _catalog.newDropsRemote(
        city: city,
        state: state,
        limit: 12,
      );
      if (!mounted) return;
      setState(() {
        _all = values[0] as List<Map<String, dynamic>>;
        _favorites = values[1] as Set<int>;
        _preferredCity = city.isEmpty ? defaultDiscoveryCity : city;
        _preferredState = state.isEmpty ? defaultDiscoveryState : state;
        _recommendedRemote = remoteRecommended;
        _dealsRemote = remoteDeals;
        _newDropsRemote = remoteDrops;
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (e) {
      final errorMessage = UIFeedback.mapDioErrorToMessage(e);
      if (!mounted) return;
      if (UIFeedback.shouldForceLogoutOn401(e)) {
        UIFeedback.showErrorSnack(
            context, 'Session expired, please sign in again.');
        await logoutToLanding(context);
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = errorMessage;
      });
      UIFeedback.showErrorSnack(context, errorMessage);
    }
  }

  Future<void> _toggleFavoriteAuthorized(Map<String, dynamic> item) async {
    final id = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id']}') ?? -1;
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

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    await requireAuthForAction(
      context,
      action: 'save listings to your watchlist',
      onAuthorized: () => _toggleFavoriteAuthorized(item),
    );
  }

  Future<void> _pickCity() async {
    final scheme = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final ctrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModal) {
            final query = ctrl.text.trim().toLowerCase();
            final rows = nigeriaTieredCities
                .where((city) =>
                    query.isEmpty || city.toLowerCase().contains(query))
                .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Choose city'),
                      subtitle: Text(
                          'City-first discovery for recommendations and search'),
                    ),
                    FTInput(
                      controller: ctrl,
                      onChanged: (_) => setModal(() {}),
                      hint: 'Search city',
                      prefixIcon: Icons.search,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 340,
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (_, index) {
                          final city = rows[index];
                          final isCurrent = city == _preferredCity;
                          return ListTile(
                            title: Text(city),
                            trailing: isCurrent
                                ? Icon(Icons.check_circle,
                                    color: scheme.primary)
                                : null,
                            onTap: () => Navigator.of(ctx).pop(city),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || selected.trim().isEmpty) return;
    await _cityPrefs.saveAndSync(
        preferredCity: selected.trim(), preferredState: _preferredState);
    if (!mounted) return;
    await _load();
  }

  void _openResults({
    String query = '',
    String sort = 'relevance',
  }) {
    Navigator.of(context).push(
      FTRoutes.page(
        child: MarketplaceSearchResultsScreen(
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
          trailing: FTSectionTextAction(
            label: 'See all',
            onPressed: () => _openResults(
              query: _searchCtrl.text.trim(),
              sort: seeAllSort,
            ),
          ),
        ),
        const SizedBox(height: FTDesignTokens.xs),
        SizedBox(
          height: 280,
          child: items.isEmpty
              ? FTCard(
                  child: FTEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'Nothing here yet',
                    subtitle: 'Try refreshing or explore all listings.',
                    primaryCtaText: 'Refresh',
                    onPrimaryCta: () => _load(showLoading: !_hasRenderableData),
                    secondaryCtaText: 'Browse categories',
                    onSecondaryCta: () => _openResults(sort: seeAllSort),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  cacheExtent: 480,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: FTDesignTokens.sm),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final id = item['id'] as int;
                    return SizedBox(
                      key: ValueKey<int>(id),
                      width: 210,
                      child: ListingCard(
                        item: item,
                        isFavorite: _favorites.contains(id),
                        onToggleFavorite: () => _toggleFavorite(item),
                        onTap: () => Navigator.of(context).push(
                          FTRoutes.page(
                            child: ListingDetailScreen(listing: item),
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
    final scheme = Theme.of(context).colorScheme;
    final recommended = _catalog.recommended(_all, limit: 10);
    final recommendedItems =
        _recommendedRemote.isNotEmpty ? _recommendedRemote : recommended;
    final trending = _catalog.trending(_all, limit: 10);
    final newest = _catalog.newest(_all, limit: 10);
    final bestValue = _catalog.bestValue(_all, limit: 10);
    final newDropsItems = _newDropsRemote.isNotEmpty ? _newDropsRemote : newest;
    final dealsItems = _dealsRemote.isNotEmpty ? _dealsRemote : bestValue;

    return FTScaffold(
      title: 'FlipTrybe Marketplace',
      actions: [
        IconButton(
          tooltip: 'Saved searches',
          onPressed: () => Navigator.of(context).push(
            FTRoutes.page(child: const SavedSearchesScreen()),
          ),
          icon: const Icon(Icons.bookmarks_outlined),
        ),
        IconButton(
          tooltip: 'Favorites',
          onPressed: () => Navigator.of(context).push(
            FTRoutes.page(child: const FavoritesScreen()),
          ),
          icon: const Icon(Icons.favorite_border),
        ),
        IconButton(
          tooltip: 'Cart',
          onPressed: () => Navigator.of(context).push(
            FTRoutes.page(child: const CartScreen()),
          ),
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => requireAuthForAction(
          context,
          action: 'create a listing',
          onAuthorized: () async {
            if (!context.mounted) return;
            await Navigator.of(context).push(
              FTRoutes.page(child: const CreateListingScreen()),
            );
          },
        ),
        icon: const Icon(Icons.add),
        label: const Text('Sell Item'),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _loading
            ? const KeyedSubtree(
                key: ValueKey<String>('marketplace_loading'),
                child: _MarketplaceSkeleton(),
              )
            : _error != null && !_hasRenderableData
                ? KeyedSubtree(
                    key: const ValueKey<String>('marketplace_error'),
                    child: FTErrorState(message: _error!, onRetry: _load),
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>('marketplace_data'),
                    child: RefreshIndicator(
                      onRefresh: () => _load(showLoading: false),
                      child: CustomScrollView(
                        cacheExtent: 960,
                        slivers: [
                          SliverAppBar(
                            pinned: true,
                            floating: true,
                            toolbarHeight: 72,
                            backgroundColor: scheme.surface,
                            surfaceTintColor: scheme.surface,
                            elevation: 0,
                            titleSpacing: 0,
                            title: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              child: TextField(
                                controller: _searchCtrl,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (value) =>
                                    _openResults(query: value),
                                style: TextStyle(color: scheme.onSurface),
                                decoration: InputDecoration(
                                  hintText: 'Search marketplace',
                                  hintStyle:
                                      TextStyle(color: scheme.onSurfaceVariant),
                                  prefixIcon: Icon(Icons.search,
                                      color: scheme.onSurfaceVariant),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.tune,
                                        color: scheme.onSurfaceVariant),
                                    tooltip: 'Open filters',
                                    onPressed: () =>
                                        _openResults(query: _searchCtrl.text),
                                  ),
                                  filled: true,
                                  fillColor: scheme.surfaceContainerHigh,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: scheme.outlineVariant),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: scheme.outlineVariant),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide:
                                        BorderSide(color: scheme.primary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Container(
                              color: scheme.surface,
                              padding: const EdgeInsets.fromLTRB(
                                FTDesignTokens.md,
                                FTDesignTokens.xs,
                                FTDesignTokens.md,
                                FTDesignTokens.lg,
                              ),
                              child: Column(
                                children: [
                                  FTCard(
                                    child: FTResponsiveTitleAction(
                                      title: 'City Discovery',
                                      subtitle:
                                          'Showing results around $_preferredCity',
                                      action: FTButton(
                                        label: _preferredCity,
                                        icon: Icons.location_city_outlined,
                                        variant: FTButtonVariant.ghost,
                                        onPressed: _pickCity,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: FTDesignTokens.sm),
                                  FTCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Explore verticals',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FTButton(
                                              label: 'Vehicles',
                                              icon: Icons.directions_car_outlined,
                                              variant: FTButtonVariant.ghost,
                                              onPressed: () => _openResults(
                                                query: 'Vehicles',
                                              ),
                                            ),
                                            FTButton(
                                              label: 'Power & Energy',
                                              icon: Icons.bolt_outlined,
                                              variant: FTButtonVariant.ghost,
                                              onPressed: () => _openResults(
                                                query: 'Solar Bundle',
                                              ),
                                            ),
                                            FTButton(
                                              label: 'Real Estate',
                                              icon: Icons.home_work_outlined,
                                              variant: FTButtonVariant.ghost,
                                              onPressed: () => _openResults(
                                                query: 'House for Rent',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: FTDesignTokens.md),
                                  if (_error != null) ...[
                                    FTCard(
                                      child: FTResponsiveTitleAction(
                                        title: 'Could not refresh feed',
                                        subtitle: _error!,
                                        action: FTButton(
                                          label: _refreshing
                                              ? 'Refreshing...'
                                              : 'Retry',
                                          icon: Icons.refresh,
                                          variant: FTButtonVariant.ghost,
                                          onPressed: _refreshing
                                              ? null
                                              : () => _load(showLoading: false),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: FTDesignTokens.md),
                                  ],
                                  _section(
                                    context,
                                    title: 'Recommended for you',
                                    subtitle:
                                        'Ranked by city, heat, freshness, and quality',
                                    items: recommendedItems,
                                    seeAllSort: 'relevance',
                                  ),
                                  const SizedBox(height: FTDesignTokens.md),
                                  _section(
                                    context,
                                    title: 'Trending near you',
                                    subtitle:
                                        'Heat-ranked listings with strong demand',
                                    items: trending,
                                    seeAllSort: 'distance',
                                  ),
                                  const SizedBox(height: FTDesignTokens.md),
                                  _section(
                                    context,
                                    title: 'New Drops',
                                    subtitle:
                                        'Fresh listings from across Nigeria',
                                    items: newDropsItems,
                                    seeAllSort: 'newest',
                                  ),
                                  const SizedBox(height: FTDesignTokens.md),
                                  _section(
                                    context,
                                    title: 'Hot Deals',
                                    subtitle:
                                        'Price-friendly picks and active offers',
                                    items: dealsItems,
                                    seeAllSort: 'price_low',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _MarketplaceSkeleton extends StatelessWidget {
  const _MarketplaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return FTSkeletonList(
      itemCount: 4,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FTDesignTokens.md,
          vertical: FTDesignTokens.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FTSkeletonLine(height: 16, widthFactor: 0.5),
            const SizedBox(height: FTDesignTokens.xs),
            const FTSkeletonLine(height: 12, widthFactor: 0.8),
            const SizedBox(height: FTDesignTokens.sm),
            SizedBox(
              height: 230,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: FTDesignTokens.sm),
                itemBuilder: (_, __) => const SizedBox(
                  width: 210,
                  child: FTCard(
                    padding: EdgeInsets.all(FTDesignTokens.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: FTSkeletonLine(height: double.infinity)),
                        SizedBox(height: FTDesignTokens.sm),
                        FTSkeletonLine(height: 14, widthFactor: 0.5),
                        SizedBox(height: FTDesignTokens.xs),
                        FTSkeletonLine(height: 12, widthFactor: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
