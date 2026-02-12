import 'dart:convert';

import 'package:flutter/material.dart';

import '../../constants/ng_states.dart';
import '../../models/marketplace_query_state.dart';
import '../../models/saved_search_record.dart';
import '../../services/marketplace_catalog_service.dart';
import '../../services/marketplace_prefs_service.dart';
import '../../ui/components/ft_components.dart';
import '../../widgets/listing/listing_card.dart';
import '../listing_detail_screen.dart';

class MarketplaceSearchResultsScreen extends StatefulWidget {
  const MarketplaceSearchResultsScreen({
    super.key,
    this.initialQuery = '',
    this.initialCategory = 'All',
    this.initialState = allNigeriaLabel,
    this.initialSort = 'relevance',
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialConditions = const [],
  });

  final String initialQuery;
  final String initialCategory;
  final String initialState;
  final String initialSort;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final List<String> initialConditions;

  @override
  State<MarketplaceSearchResultsScreen> createState() =>
      _MarketplaceSearchResultsScreenState();
}

class _MarketplaceSearchResultsScreenState
    extends State<MarketplaceSearchResultsScreen> {
  final _catalog = MarketplaceCatalogService();
  final _prefs = MarketplacePrefsService();
  final _queryCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _filtered = const [];
  Set<int> _favorites = <int>{};
  late MarketplaceQueryState _queryState;

  static const _categories = [
    'All',
    'Phones',
    'Fashion',
    'Furniture',
    'Electronics',
    'Home',
    'Sports',
  ];

  static const _sortOptions = {
    'relevance': 'Relevance',
    'newest': 'Newest',
    'price_low': 'Price: Low to High',
    'price_high': 'Price: High to Low',
    'distance': 'Distance',
  };

  static const _conditionOptions = [
    'new',
    'like new',
    'good',
    'fair',
  ];

  @override
  void initState() {
    super.initState();
    _queryState = MarketplaceQueryState(
      query: widget.initialQuery,
      category: widget.initialCategory,
      state: widget.initialState,
      sort: widget.initialSort,
      minPrice: widget.initialMinPrice,
      maxPrice: widget.initialMaxPrice,
      conditions: widget.initialConditions,
    );
    _queryCtrl.text = _queryState.query;
    _boot();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
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
      _all = values[0] as List<Map<String, dynamic>>;
      _favorites = values[1] as Set<int>;
      _apply();
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load results. Check your connection and retry.';
      });
    }
  }

  void _apply() {
    _filtered = _catalog.applyFilters(
      _all,
      query: _queryCtrl.text,
      category: _queryState.category,
      state: _queryState.state,
      minPrice: _queryState.minPrice,
      maxPrice: _queryState.maxPrice,
      conditions: _queryState.conditions,
      sort: _queryState.sort,
    );
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
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

  Future<void> _saveCurrentSearch() async {
    final state = _queryState.copyWith(query: _queryCtrl.text.trim());
    final payload = state.toMap();
    final key = base64Encode(utf8.encode(jsonEncode(payload)));
    final now = DateTime.now().toUtc();
    await _prefs.upsertSearch(
      SavedSearchRecord(
        key: key,
        state: state,
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search saved.')),
    );
  }

  Future<void> _openFilters() async {
    final minCtrl =
        TextEditingController(text: _queryState.minPrice?.toStringAsFixed(0) ?? '');
    final maxCtrl =
        TextEditingController(text: _queryState.maxPrice?.toStringAsFixed(0) ?? '');
    String draftCategory = _queryState.category;
    String draftState = _queryState.state;
    final draftConditions = <String>{..._queryState.conditions};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FTSectionHeader(title: 'Filters'),
                    const SizedBox(height: 10),
                    const Text('Category',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories
                          .map((c) => FTChip(
                                label: c,
                                selected: draftCategory == c,
                                onTap: () => setModal(() => draftCategory = c),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text('State',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: draftState,
                      items: [allNigeriaLabel, ...nigeriaStates]
                          .map((s) => DropdownMenuItem(
                              value: s, child: Text(displayState(s))))
                          .toList(),
                      onChanged: (value) =>
                          setModal(() => draftState = value ?? allNigeriaLabel),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Min price (₦)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Max price (₦)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Condition',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _conditionOptions
                          .map((condition) => FilterChip(
                                label: Text(condition),
                                selected: draftConditions.contains(condition),
                                onSelected: (selected) {
                                  setModal(() {
                                    if (selected) {
                                      draftConditions.add(condition);
                                    } else {
                                      draftConditions.remove(condition);
                                    }
                                  });
                                },
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text('Distance',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.near_me_disabled_outlined),
                      title: Text('Distance filter'),
                      subtitle: Text('Coming soon (location radius support).'),
                    ),
                    const SizedBox(height: 6),
                    const Text('Delivery / Inspection',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      value: false,
                      onChanged: null,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delivery available'),
                      subtitle: const Text('Coming soon'),
                    ),
                    CheckboxListTile(
                      value: false,
                      onChanged: null,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Inspection available'),
                      subtitle: const Text('Coming soon'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FTSecondaryButton(
                            label: 'Clear',
                            icon: Icons.restart_alt,
                            onPressed: () {
                              setModal(() {
                                draftCategory = 'All';
                                draftState = allNigeriaLabel;
                                draftConditions.clear();
                                minCtrl.clear();
                                maxCtrl.clear();
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FTPrimaryButton(
                            label: 'Apply',
                            icon: Icons.check,
                            onPressed: () {
                              setState(() {
                                _queryState = _queryState.copyWith(
                                  category: draftCategory,
                                  state: draftState,
                                  conditions: draftConditions.toList(),
                                  minPrice:
                                      double.tryParse(minCtrl.text.trim()),
                                  maxPrice:
                                      double.tryParse(maxCtrl.text.trim()),
                                );
                                _apply();
                              });
                              Navigator.of(ctx).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _activeFilterChips() {
    final chips = <Widget>[];
    if (_queryState.category != 'All') {
      chips.add(FTChip(
          label: 'Category: ${_queryState.category}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(category: 'All');
              _apply();
            });
          }));
    }
    if (_queryState.state != allNigeriaLabel) {
      chips.add(FTChip(
          label: displayState(_queryState.state),
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(state: allNigeriaLabel);
              _apply();
            });
          }));
    }
    if (_queryState.minPrice != null || _queryState.maxPrice != null) {
      chips.add(FTChip(
          label:
              '₦${_queryState.minPrice?.toStringAsFixed(0) ?? '0'} - ₦${_queryState.maxPrice?.toStringAsFixed(0) ?? '∞'}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                clearMinPrice: true,
                clearMaxPrice: true,
              );
              _apply();
            });
          }));
    }
    for (final c in _queryState.conditions) {
      chips.add(FTChip(
          label: c,
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                conditions: _queryState.conditions
                    .where((item) => item != c)
                    .toList(growable: false),
              );
              _apply();
            });
          }));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final chips = _activeFilterChips();
    return FTScaffold(
      title: 'Search Results',
      actions: [
        IconButton(
          tooltip: 'Save this search',
          onPressed: _saveCurrentSearch,
          icon: const Icon(Icons.bookmark_add_outlined),
        ),
      ],
      child: _loading
          ? const _ResultsSkeleton()
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _boot)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: _queryCtrl,
                            decoration: InputDecoration(
                              hintText: 'Search listings',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.mic_none_outlined),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Voice search coming soon.')),
                                  );
                                },
                              ),
                            ),
                            onSubmitted: (_) => setState(_apply),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FTSecondaryButton(
                                  label: 'Sort',
                                  icon: Icons.swap_vert,
                                  onPressed: () async {
                                    final selected =
                                        await showModalBottomSheet<String>(
                                      context: context,
                                      builder: (_) => SafeArea(
                                        child: ListView(
                                          shrinkWrap: true,
                                          children: _sortOptions.entries
                                              .map((entry) =>
                                                  RadioListTile<String>(
                                                    value: entry.key,
                                                    groupValue: _queryState.sort,
                                                    onChanged: (value) {
                                                      Navigator.of(context)
                                                          .pop(value);
                                                    },
                                                    title: Text(entry.value),
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                    );
                                    if (selected == null) return;
                                    setState(() {
                                      _queryState =
                                          _queryState.copyWith(sort: selected);
                                      _apply();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FTSecondaryButton(
                                  label: 'Filters',
                                  icon: Icons.tune,
                                  onPressed: _openFilters,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: _queryState.gridView
                                    ? 'Switch to list'
                                    : 'Switch to grid',
                                onPressed: () => setState(() {
                                  _queryState = _queryState.copyWith(
                                    gridView: !_queryState.gridView,
                                  );
                                }),
                                icon: Icon(_queryState.gridView
                                    ? Icons.view_list_outlined
                                    : Icons.grid_view_outlined),
                              ),
                            ],
                          ),
                          if (chips.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                    spacing: 8, runSpacing: 8, children: chips),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? FTEmptyState(
                              icon: Icons.search_off_outlined,
                              title: 'No listings found',
                              subtitle:
                                  'Try changing filters or search terms. You can also clear filters and browse nationwide.',
                              actionLabel: 'Clear filters',
                              onAction: () {
                                setState(() {
                                  _queryState = _queryState.copyWith(
                                    category: 'All',
                                    state: allNigeriaLabel,
                                    conditions: const <String>[],
                                    sort: 'relevance',
                                    clearMinPrice: true,
                                    clearMaxPrice: true,
                                  );
                                  _apply();
                                });
                              },
                            )
                          : RefreshIndicator(
                              onRefresh: _boot,
                              child: _queryState.gridView
                                  ? GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 20),
                                      itemCount: _filtered.length,
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio: 0.64,
                                      ),
                                      itemBuilder: (_, index) {
                                        final item = _filtered[index];
                                        final id = item['id'] as int;
                                        return ListingCard(
                                          item: item,
                                          isFavorite: _favorites.contains(id),
                                          onToggleFavorite: () =>
                                              _toggleFavorite(item),
                                          onTap: () =>
                                              Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ListingDetailScreen(
                                                      listing: item),
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 20),
                                      itemCount: _filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 12),
                                      itemBuilder: (_, index) {
                                        final item = _filtered[index];
                                        final id = item['id'] as int;
                                        return SizedBox(
                                          height: 190,
                                          child: ListingCard(
                                            item: item,
                                            compact: true,
                                            isFavorite: _favorites.contains(id),
                                            onToggleFavorite: () =>
                                                _toggleFavorite(item),
                                            onTap: () =>
                                                Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ListingDetailScreen(
                                                        listing: item),
                                              ),
                                            ),
                                          ),
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

class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const FTSkeleton(height: 48),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(child: FTSkeleton(height: 40)),
              SizedBox(width: 8),
              Expanded(child: FTSkeleton(height: 40)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.64,
              ),
              itemBuilder: (_, __) => const FTCard(
                padding: EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: FTSkeleton(height: double.infinity)),
                    SizedBox(height: 8),
                    FTSkeleton(height: 16, width: 90),
                    SizedBox(height: 6),
                    FTSkeleton(height: 14),
                    SizedBox(height: 4),
                    FTSkeleton(height: 12, width: 120),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
