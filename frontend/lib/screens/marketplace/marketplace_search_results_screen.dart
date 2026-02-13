import 'dart:convert';

import 'package:flutter/material.dart';

import '../../constants/ng_states.dart';
import '../../models/marketplace_query_state.dart';
import '../../models/saved_search_record.dart';
import '../../services/category_service.dart';
import '../../services/auth_gate_service.dart';
import '../../services/marketplace_catalog_service.dart';
import '../../services/marketplace_prefs_service.dart';
import '../../ui/components/ft_components.dart';
import '../../utils/formatters.dart';
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
  final _categorySvc = CategoryService();
  final _queryCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _filtered = const [];
  Set<int> _favorites = <int>{};
  late MarketplaceQueryState _queryState;
  String _searchMode = 'off';
  bool _syncingRemote = false;
  int _shadowRemoteCount = 0;
  bool _supportsDeliveryFilter = false;
  bool _supportsInspectionFilter = false;
  List<Map<String, dynamic>> _taxonomy = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _brandOptions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _modelOptions = const <Map<String, dynamic>>[];

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

  List<Map<String, dynamic>> _flattenCategories(
      List<Map<String, dynamic>> tree) {
    final out = <Map<String, dynamic>>[];
    void walk(Map<String, dynamic> row) {
      out.add(row);
      final children = (row['children'] is List)
          ? (row['children'] as List)
              .whereType<Map>()
              .map((child) => Map<String, dynamic>.from(child))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      for (final child in children) {
        walk(child);
      }
    }

    for (final row in tree) {
      walk(row);
    }
    return out;
  }

  List<Map<String, dynamic>> _topCategories() {
    return _taxonomy
        .where((row) => row['parent_id'] == null)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _leafCategoriesForParent(int? parentId) {
    if (parentId == null) return const <Map<String, dynamic>>[];
    return _taxonomy
        .where((row) => int.tryParse('${row['parent_id'] ?? ''}') == parentId)
        .toList(growable: false);
  }

  Future<void> _reloadTaxonomyFilters() async {
    final data = await _categorySvc.filters(
      categoryId: _queryState.categoryId ?? _queryState.parentCategoryId,
      brandId: _queryState.brandId,
    );
    if (!mounted) return;
    setState(() {
      _brandOptions = data['brands'] ?? const <Map<String, dynamic>>[];
      _modelOptions = data['models'] ?? const <Map<String, dynamic>>[];
    });
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
        _catalog.searchV2Mode(),
        _categorySvc.categoriesTree(),
      ]);
      if (!mounted) return;
      _all = values[0] as List<Map<String, dynamic>>;
      _favorites = values[1] as Set<int>;
      _searchMode = (values[2] as String).toLowerCase();
      _taxonomy = _flattenCategories(
        (values[3] as List<Map<String, dynamic>>),
      );
      _apply();
      setState(() => _loading = false);
      _reloadTaxonomyFilters();
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
      categoryId: _queryState.categoryId,
      parentCategoryId: _queryState.parentCategoryId,
      brandId: _queryState.brandId,
      modelId: _queryState.modelId,
      state: _queryState.state,
      minPrice: _queryState.minPrice,
      maxPrice: _queryState.maxPrice,
      conditions: _queryState.conditions,
      sort: _queryState.sort,
    );
    Future.microtask(_syncSearchV2);
  }

  Future<void> _syncSearchV2() async {
    if (_syncingRemote) return;
    if (_searchMode == 'off') return;
    _syncingRemote = true;
    try {
      final firstCondition =
          _queryState.conditions.isNotEmpty ? _queryState.conditions.first : '';
      final remoteResult = await _catalog.searchRemoteDetailed(
        query: _queryCtrl.text.trim(),
        category: _queryState.category,
        categoryId: _queryState.categoryId,
        parentCategoryId: _queryState.parentCategoryId,
        brandId: _queryState.brandId,
        modelId: _queryState.modelId,
        state: _queryState.state,
        minPrice: _queryState.minPrice,
        maxPrice: _queryState.maxPrice,
        condition: firstCondition,
        deliveryAvailable: _queryState.deliveryAvailable
            ? _queryState.deliveryAvailable
            : null,
        inspectionRequired: _queryState.inspectionRequired
            ? _queryState.inspectionRequired
            : null,
        sort: _queryState.sort,
        limit: 60,
      );
      final remote = remoteResult.items;
      final supportsDelivery =
          remoteResult.supportedFilters['delivery_available'] == true;
      final supportsInspection =
          remoteResult.supportedFilters['inspection_required'] == true;
      if (!mounted) return;
      if (_searchMode == 'on') {
        setState(() {
          _filtered = remote;
          _supportsDeliveryFilter = supportsDelivery;
          _supportsInspectionFilter = supportsInspection;
        });
      } else if (_searchMode == 'shadow') {
        setState(() {
          _shadowRemoteCount = remote.length;
          _supportsDeliveryFilter = supportsDelivery;
          _supportsInspectionFilter = supportsInspection;
        });
      }
    } catch (_) {
      // ignore remote sync failures; local filtering remains authoritative in off/shadow mode.
    } finally {
      _syncingRemote = false;
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
    final minCtrl = TextEditingController(
        text: _queryState.minPrice?.toStringAsFixed(0) ?? '');
    final maxCtrl = TextEditingController(
        text: _queryState.maxPrice?.toStringAsFixed(0) ?? '');
    String draftCategory = _queryState.category;
    int? draftParentCategoryId = _queryState.parentCategoryId;
    int? draftCategoryId = _queryState.categoryId;
    int? draftBrandId = _queryState.brandId;
    int? draftModelId = _queryState.modelId;
    String draftState = _queryState.state;
    final draftConditions = <String>{..._queryState.conditions};
    bool draftDelivery = _queryState.deliveryAvailable;
    bool draftInspection = _queryState.inspectionRequired;
    var draftBrands = List<Map<String, dynamic>>.from(_brandOptions);
    var draftModels = List<Map<String, dynamic>>.from(_modelOptions);

    Future<void> loadDraftFilters(StateSetter setModal) async {
      final data = await _categorySvc.filters(
        categoryId: draftCategoryId ?? draftParentCategoryId,
        brandId: draftBrandId,
      );
      draftBrands = data['brands'] ?? const <Map<String, dynamic>>[];
      draftModels = data['models'] ?? const <Map<String, dynamic>>[];
      setModal(() {
        if (draftBrandId != null &&
            !draftBrands.any(
                (row) => int.tryParse('${row['id'] ?? ''}') == draftBrandId)) {
          draftBrandId = null;
        }
        if (draftModelId != null &&
            !draftModels.any(
                (row) => int.tryParse('${row['id'] ?? ''}') == draftModelId)) {
          draftModelId = null;
        }
      });
    }

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
                    if (_topCategories().isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        initialValue: draftParentCategoryId,
                        items: _topCategories()
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: int.tryParse('${row['id']}'),
                                child: Text((row['name'] ?? '').toString()),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) async {
                          setModal(() {
                            draftParentCategoryId = value;
                            draftCategoryId = null;
                            draftBrandId = null;
                            draftModelId = null;
                          });
                          await loadDraftFilters(setModal);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Category group',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: draftCategoryId,
                        items: _leafCategoriesForParent(draftParentCategoryId)
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: int.tryParse('${row['id']}'),
                                child: Text((row['name'] ?? '').toString()),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) async {
                          setModal(() {
                            draftCategoryId = value;
                            final row =
                                _leafCategoriesForParent(draftParentCategoryId)
                                    .firstWhere(
                              (entry) =>
                                  int.tryParse('${entry['id']}') == value,
                              orElse: () => const <String, dynamic>{},
                            );
                            draftCategory =
                                (row['name'] ?? draftCategory).toString();
                            draftBrandId = null;
                            draftModelId = null;
                          });
                          await loadDraftFilters(setModal);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: draftBrandId,
                        items: draftBrands
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: int.tryParse('${row['id']}'),
                                child: Text((row['name'] ?? '').toString()),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) async {
                          setModal(() {
                            draftBrandId = value;
                            draftModelId = null;
                          });
                          await loadDraftFilters(setModal);
                        },
                        decoration: const InputDecoration(
                            labelText: 'Brand (optional)'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: draftModelId,
                        items: draftModels
                            .map(
                              (row) => DropdownMenuItem<int>(
                                value: int.tryParse('${row['id']}'),
                                child: Text((row['name'] ?? '').toString()),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) =>
                            setModal(() => draftModelId = value),
                        decoration: const InputDecoration(
                            labelText: 'Model (optional)'),
                      ),
                    ] else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categories
                            .map((c) => FTChip(
                                  label: c,
                                  selected: draftCategory == c,
                                  onTap: () =>
                                      setModal(() => draftCategory = c),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 14),
                    const Text('State',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: draftState,
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
                                labelText: 'Min price (\u20A6)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: maxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                                labelText: 'Max price (\u20A6)'),
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
                      value: draftDelivery,
                      onChanged: _supportsDeliveryFilter
                          ? (next) =>
                              setModal(() => draftDelivery = next == true)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Delivery available'),
                      subtitle: Text(_supportsDeliveryFilter
                          ? 'Filter listings with delivery support'
                          : 'Coming soon'),
                    ),
                    CheckboxListTile(
                      value: draftInspection,
                      onChanged: _supportsInspectionFilter
                          ? (next) =>
                              setModal(() => draftInspection = next == true)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Inspection available'),
                      subtitle: Text(_supportsInspectionFilter
                          ? 'Filter listings with inspection support'
                          : 'Coming soon'),
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
                                draftParentCategoryId = null;
                                draftCategoryId = null;
                                draftBrandId = null;
                                draftModelId = null;
                                draftState = allNigeriaLabel;
                                draftConditions.clear();
                                draftDelivery = false;
                                draftInspection = false;
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
                                  parentCategoryId: draftParentCategoryId,
                                  categoryId: draftCategoryId,
                                  brandId: draftBrandId,
                                  modelId: draftModelId,
                                  state: draftState,
                                  conditions: draftConditions.toList(),
                                  minPrice:
                                      double.tryParse(minCtrl.text.trim()),
                                  maxPrice:
                                      double.tryParse(maxCtrl.text.trim()),
                                  deliveryAvailable: draftDelivery,
                                  inspectionRequired: draftInspection,
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
              _queryState = _queryState.copyWith(
                category: 'All',
                clearCategoryId: true,
                clearParentCategoryId: true,
                clearBrandId: true,
                clearModelId: true,
              );
              _apply();
            });
          }));
    }
    if (_queryState.brandId != null) {
      chips.add(FTChip(
          label: 'Brand #${_queryState.brandId}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                clearBrandId: true,
                clearModelId: true,
              );
              _apply();
            });
          }));
    }
    if (_queryState.modelId != null) {
      chips.add(FTChip(
          label: 'Model #${_queryState.modelId}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(clearModelId: true);
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
              '${formatNaira(_queryState.minPrice ?? 0, decimals: 0)} - ${_queryState.maxPrice == null ? "No max" : formatNaira(_queryState.maxPrice!, decimals: 0)}',
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
    if (_queryState.deliveryAvailable) {
      chips.add(FTChip(
          label: 'Delivery available',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(deliveryAvailable: false);
              _apply();
            });
          }));
    }
    if (_queryState.inspectionRequired) {
      chips.add(FTChip(
          label: 'Inspection available',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(inspectionRequired: false);
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
                                                    groupValue:
                                                        _queryState.sort,
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
                          if (_searchMode == 'shadow')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Search V2 shadow active (remote hits: $_shadowRemoteCount)',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
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
