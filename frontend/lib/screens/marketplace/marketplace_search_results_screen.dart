import 'package:flutter/material.dart';

import '../../constants/ng_states.dart';
import '../../models/marketplace_query_state.dart';
import '../../services/category_service.dart';
import '../../services/auth_gate_service.dart';
import '../../services/marketplace_catalog_service.dart';
import '../../services/marketplace_prefs_service.dart';
import '../../services/saved_search_service.dart';
import '../../ui/components/ft_components.dart';
import '../../utils/formatters.dart';
import '../../widgets/listing/listing_card.dart';
import '../listing_detail_screen.dart';

class MarketplaceSearchResultsScreen extends StatefulWidget {
  const MarketplaceSearchResultsScreen({
    super.key,
    this.initialQueryState,
    this.initialQuery = '',
    this.initialCategory = 'All',
    this.initialState = allNigeriaLabel,
    this.initialSort = 'relevance',
    this.initialMinPrice,
    this.initialMaxPrice,
    this.initialConditions = const [],
  });

  final MarketplaceQueryState? initialQueryState;
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
  final _savedSearches = SavedSearchService();
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

  static const _categories = ['All'];

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
    _queryState = widget.initialQueryState ??
        MarketplaceQueryState(
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

  List<Map<String, dynamic>> _categorySuggestionsForQuery(String rawQuery) {
    final q = rawQuery.trim().toLowerCase();
    if (q.length < 2) return const <Map<String, dynamic>>[];
    return _taxonomy
        .where((row) => (row['name'] ?? '').toString().toLowerCase().contains(q))
        .take(8)
        .map((row) => Map<String, dynamic>.from(row))
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
        _prefs.loadLastCategoryContext(),
      ]);
      if (!mounted) return;
      _all = values[0] as List<Map<String, dynamic>>;
      _favorites = values[1] as Set<int>;
      _searchMode = (values[2] as String).toLowerCase();
      _taxonomy = _flattenCategories(
        (values[3] as List<Map<String, dynamic>>),
      );
      final lastCategory = (values[4] is Map)
          ? Map<String, dynamic>.from(values[4] as Map)
          : const <String, dynamic>{};
      if ((_queryState.category == 'All' || _queryState.category.trim().isEmpty) &&
          _queryState.categoryId == null &&
          lastCategory.isNotEmpty) {
        _queryState = _queryState.copyWith(
          category: (lastCategory['category'] ?? 'All').toString(),
          categoryId: lastCategory['categoryId'] is num
              ? (lastCategory['categoryId'] as num).toInt()
              : int.tryParse((lastCategory['categoryId'] ?? '').toString()),
          parentCategoryId: lastCategory['parentCategoryId'] is num
              ? (lastCategory['parentCategoryId'] as num).toInt()
              : int.tryParse((lastCategory['parentCategoryId'] ?? '').toString()),
        );
      }
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
      listingType: _queryState.listingType,
      make: _queryState.vehicleMake,
      model: _queryState.vehicleModel,
      year: _queryState.vehicleYear,
      batteryType: _queryState.batteryType,
      inverterCapacity: _queryState.inverterCapacity,
      lithiumOnly: _queryState.lithiumOnly,
      propertyType: _queryState.propertyType,
      bedroomsMin: _queryState.bedroomsMin,
      bedroomsMax: _queryState.bedroomsMax,
      bathroomsMin: _queryState.bathroomsMin,
      bathroomsMax: _queryState.bathroomsMax,
      furnishedOnly: _queryState.furnishedOnly,
      servicedOnly: _queryState.servicedOnly,
      landSizeMin: _queryState.landSizeMin,
      landSizeMax: _queryState.landSizeMax,
      titleDocumentType: _queryState.titleDocumentType,
      city: _queryState.city,
      area: _queryState.area,
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
        listingType: _queryState.listingType,
        make: _queryState.vehicleMake,
        model: _queryState.vehicleModel,
        year: _queryState.vehicleYear,
        batteryType: _queryState.batteryType,
        inverterCapacity: _queryState.inverterCapacity,
        lithiumOnly: _queryState.lithiumOnly ? true : null,
        propertyType: _queryState.propertyType,
        bedroomsMin: _queryState.bedroomsMin,
        bedroomsMax: _queryState.bedroomsMax,
        bathroomsMin: _queryState.bathroomsMin,
        bathroomsMax: _queryState.bathroomsMax,
        furnished: _queryState.furnishedOnly ? true : null,
        serviced: _queryState.servicedOnly ? true : null,
        landSizeMin: _queryState.landSizeMin,
        landSizeMax: _queryState.landSizeMax,
        titleDocumentType: _queryState.titleDocumentType,
        city: _queryState.city,
        area: _queryState.area,
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
    final vertical = _inferVertical(state);
    payload['vertical'] = vertical;
    final create = await _savedSearches.create(
      name: state.query.trim().isEmpty ? 'Saved search' : state.query.trim(),
      vertical: vertical,
      queryJson: payload,
    );
    if (create['ok'] != true) {
      if (!mounted) return;
      final msg = (create['message'] ?? 'Unable to save search').toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Search saved.')),
    );
  }

  String _inferVertical(MarketplaceQueryState state) {
    final listingType = state.listingType.trim().toLowerCase();
    if (listingType == 'vehicle') return 'vehicles';
    if (listingType == 'energy') return 'energy';
    if (listingType == 'real_estate') return 'real_estate';
    final category = state.category.toLowerCase();
    if (category.contains('car') ||
        category.contains('truck') ||
        category.contains('motorcycle') ||
        category.contains('vehicle')) {
      return 'vehicles';
    }
    if (category.contains('solar') ||
        category.contains('inverter') ||
        category.contains('battery') ||
        category.contains('energy')) {
      return 'energy';
    }
    if (category.contains('house') ||
        category.contains('land') ||
        category.contains('real estate')) {
      return 'real_estate';
    }
    return 'marketplace';
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
    String draftListingType = _queryState.listingType;
    final draftMakeCtrl = TextEditingController(text: _queryState.vehicleMake);
    final draftVehicleModelCtrl =
        TextEditingController(text: _queryState.vehicleModel);
    final draftVehicleYearCtrl = TextEditingController(
        text: _queryState.vehicleYear?.toString() ?? '');
    final draftBatteryTypeCtrl =
        TextEditingController(text: _queryState.batteryType);
    final draftInverterCapacityCtrl =
        TextEditingController(text: _queryState.inverterCapacity);
    bool draftLithiumOnly = _queryState.lithiumOnly;
    String draftPropertyType = _queryState.propertyType;
    final draftBedroomsMinCtrl = TextEditingController(
      text: _queryState.bedroomsMin?.toString() ?? '',
    );
    final draftBedroomsMaxCtrl = TextEditingController(
      text: _queryState.bedroomsMax?.toString() ?? '',
    );
    final draftBathroomsMinCtrl = TextEditingController(
      text: _queryState.bathroomsMin?.toString() ?? '',
    );
    final draftBathroomsMaxCtrl = TextEditingController(
      text: _queryState.bathroomsMax?.toString() ?? '',
    );
    bool draftFurnishedOnly = _queryState.furnishedOnly;
    bool draftServicedOnly = _queryState.servicedOnly;
    final draftLandSizeMinCtrl = TextEditingController(
      text: _queryState.landSizeMin?.toStringAsFixed(0) ?? '',
    );
    final draftLandSizeMaxCtrl = TextEditingController(
      text: _queryState.landSizeMax?.toStringAsFixed(0) ?? '',
    );
    final draftTitleDocCtrl =
        TextEditingController(text: _queryState.titleDocumentType);
    final draftCityCtrl = TextEditingController(text: _queryState.city);
    final draftAreaCtrl = TextEditingController(text: _queryState.area);
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
                    const Text('Vertical filters',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: draftListingType.isEmpty ? null : draftListingType,
                      items: const [
                        DropdownMenuItem(value: 'vehicle', child: Text('Vehicle')),
                        DropdownMenuItem(value: 'energy', child: Text('Power & Energy')),
                        DropdownMenuItem(
                            value: 'real_estate', child: Text('Real Estate')),
                      ],
                      onChanged: (value) =>
                          setModal(() => draftListingType = value ?? ''),
                      decoration: const InputDecoration(
                        labelText: 'Listing type',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draftMakeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Make',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: draftVehicleModelCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Model',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draftVehicleYearCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Year',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draftBatteryTypeCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Battery type',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: draftInverterCapacityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Inverter capacity',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      value: draftLithiumOnly,
                      onChanged: (next) =>
                          setModal(() => draftLithiumOnly = next),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lithium only'),
                    ),
                    const SizedBox(height: 10),
                    const Text('Real estate filters',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: draftPropertyType.isEmpty ? null : draftPropertyType,
                      items: const [
                        DropdownMenuItem(value: 'Rent', child: Text('Rent')),
                        DropdownMenuItem(value: 'Sale', child: Text('Sale')),
                        DropdownMenuItem(value: 'Land', child: Text('Land')),
                      ],
                      onChanged: (value) =>
                          setModal(() => draftPropertyType = value ?? ''),
                      decoration:
                          const InputDecoration(labelText: 'Property type'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draftBedroomsMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bedrooms min',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: draftBedroomsMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bedrooms max',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draftBathroomsMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bathrooms min',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: draftBathroomsMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Bathrooms max',
                            ),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile.adaptive(
                      value: draftFurnishedOnly,
                      onChanged: (next) =>
                          setModal(() => draftFurnishedOnly = next),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Furnished only'),
                    ),
                    SwitchListTile.adaptive(
                      value: draftServicedOnly,
                      onChanged: (next) =>
                          setModal(() => draftServicedOnly = next),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Serviced only'),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draftLandSizeMinCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Land size min',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: draftLandSizeMaxCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Land size max',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draftTitleDocCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Title document type',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draftCityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'City',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: draftAreaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Area',
                      ),
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
                                draftListingType = '';
                                draftLithiumOnly = false;
                                draftPropertyType = '';
                                draftFurnishedOnly = false;
                                draftServicedOnly = false;
                                minCtrl.clear();
                                maxCtrl.clear();
                                draftMakeCtrl.clear();
                                draftVehicleModelCtrl.clear();
                                draftVehicleYearCtrl.clear();
                                draftBatteryTypeCtrl.clear();
                                draftInverterCapacityCtrl.clear();
                                draftBedroomsMinCtrl.clear();
                                draftBedroomsMaxCtrl.clear();
                                draftBathroomsMinCtrl.clear();
                                draftBathroomsMaxCtrl.clear();
                                draftLandSizeMinCtrl.clear();
                                draftLandSizeMaxCtrl.clear();
                                draftTitleDocCtrl.clear();
                                draftCityCtrl.clear();
                                draftAreaCtrl.clear();
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
                                  listingType: draftListingType,
                                  vehicleMake: draftMakeCtrl.text.trim(),
                                  vehicleModel:
                                      draftVehicleModelCtrl.text.trim(),
                                  vehicleYear:
                                      int.tryParse(draftVehicleYearCtrl.text),
                                  batteryType:
                                      draftBatteryTypeCtrl.text.trim(),
                                  inverterCapacity:
                                      draftInverterCapacityCtrl.text.trim(),
                                  lithiumOnly: draftLithiumOnly,
                                  propertyType: draftPropertyType,
                                  bedroomsMin:
                                      int.tryParse(draftBedroomsMinCtrl.text),
                                  bedroomsMax:
                                      int.tryParse(draftBedroomsMaxCtrl.text),
                                  bathroomsMin:
                                      int.tryParse(draftBathroomsMinCtrl.text),
                                  bathroomsMax:
                                      int.tryParse(draftBathroomsMaxCtrl.text),
                                  furnishedOnly: draftFurnishedOnly,
                                  servicedOnly: draftServicedOnly,
                                  landSizeMin:
                                      double.tryParse(draftLandSizeMinCtrl.text),
                                  landSizeMax:
                                      double.tryParse(draftLandSizeMaxCtrl.text),
                                  titleDocumentType:
                                      draftTitleDocCtrl.text.trim(),
                                  city: draftCityCtrl.text.trim(),
                                  area: draftAreaCtrl.text.trim(),
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
                              _prefs.saveLastCategoryContext(
                                category: draftCategory,
                                categoryId: draftCategoryId,
                                parentCategoryId: draftParentCategoryId,
                              );
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
    if (_queryState.listingType.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Type: ${_queryState.listingType}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(listingType: '');
              _apply();
            });
          }));
    }
    if (_queryState.vehicleMake.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Make: ${_queryState.vehicleMake}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(vehicleMake: '');
              _apply();
            });
          }));
    }
    if (_queryState.vehicleModel.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Vehicle model: ${_queryState.vehicleModel}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(vehicleModel: '');
              _apply();
            });
          }));
    }
    if (_queryState.vehicleYear != null) {
      chips.add(FTChip(
          label: 'Year: ${_queryState.vehicleYear}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(clearVehicleYear: true);
              _apply();
            });
          }));
    }
    if (_queryState.batteryType.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Battery: ${_queryState.batteryType}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(batteryType: '');
              _apply();
            });
          }));
    }
    if (_queryState.inverterCapacity.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Inverter: ${_queryState.inverterCapacity}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(inverterCapacity: '');
              _apply();
            });
          }));
    }
    if (_queryState.lithiumOnly) {
      chips.add(FTChip(
          label: 'Lithium only',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(lithiumOnly: false);
              _apply();
            });
          }));
    }
    if (_queryState.propertyType.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Property: ${_queryState.propertyType}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(propertyType: '');
              _apply();
            });
          }));
    }
    if (_queryState.bedroomsMin != null || _queryState.bedroomsMax != null) {
      chips.add(FTChip(
          label:
              'Beds: ${_queryState.bedroomsMin ?? '-'} to ${_queryState.bedroomsMax ?? '-'}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                clearBedroomsMin: true,
                clearBedroomsMax: true,
              );
              _apply();
            });
          }));
    }
    if (_queryState.bathroomsMin != null || _queryState.bathroomsMax != null) {
      chips.add(FTChip(
          label:
              'Baths: ${_queryState.bathroomsMin ?? '-'} to ${_queryState.bathroomsMax ?? '-'}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                clearBathroomsMin: true,
                clearBathroomsMax: true,
              );
              _apply();
            });
          }));
    }
    if (_queryState.furnishedOnly) {
      chips.add(FTChip(
          label: 'Furnished',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(furnishedOnly: false);
              _apply();
            });
          }));
    }
    if (_queryState.servicedOnly) {
      chips.add(FTChip(
          label: 'Serviced',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(servicedOnly: false);
              _apply();
            });
          }));
    }
    if (_queryState.landSizeMin != null || _queryState.landSizeMax != null) {
      chips.add(FTChip(
          label:
              'Land: ${_queryState.landSizeMin ?? '-'} to ${_queryState.landSizeMax ?? '-'}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(
                clearLandSizeMin: true,
                clearLandSizeMax: true,
              );
              _apply();
            });
          }));
    }
    if (_queryState.titleDocumentType.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Doc: ${_queryState.titleDocumentType}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(titleDocumentType: '');
              _apply();
            });
          }));
    }
    if (_queryState.city.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'City: ${_queryState.city}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(city: '');
              _apply();
            });
          }));
    }
    if (_queryState.area.trim().isNotEmpty) {
      chips.add(FTChip(
          label: 'Area: ${_queryState.area}',
          selected: true,
          onTap: () {
            setState(() {
              _queryState = _queryState.copyWith(area: '');
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
    final categorySuggestions = _categorySuggestionsForQuery(_queryCtrl.text);
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
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => setState(_apply),
                          ),
                          if (categorySuggestions.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: categorySuggestions.map((row) {
                                  final label = (row['name'] ?? '').toString();
                                  return ActionChip(
                                    label: Text(label),
                                    onPressed: () {
                                      setState(() {
                                        _queryState = _queryState.copyWith(
                                          category: label,
                                          categoryId: int.tryParse('${row['id'] ?? ''}'),
                                          parentCategoryId:
                                              int.tryParse('${row['parent_id'] ?? ''}'),
                                        );
                                        _apply();
                                      });
                                      _prefs.saveLastCategoryContext(
                                        category: label,
                                        categoryId: int.tryParse('${row['id'] ?? ''}'),
                                        parentCategoryId:
                                            int.tryParse('${row['parent_id'] ?? ''}'),
                                      );
                                    },
                                  );
                                }).toList(growable: false),
                              ),
                            ),
                          ],
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
                                    clearCategoryId: true,
                                    clearParentCategoryId: true,
                                    clearBrandId: true,
                                    clearModelId: true,
                                    state: allNigeriaLabel,
                                    conditions: const <String>[],
                                    sort: 'relevance',
                                    listingType: '',
                                    vehicleMake: '',
                                    vehicleModel: '',
                                    clearVehicleYear: true,
                                    batteryType: '',
                                    inverterCapacity: '',
                                    lithiumOnly: false,
                                    propertyType: '',
                                    clearBedroomsMin: true,
                                    clearBedroomsMax: true,
                                    clearBathroomsMin: true,
                                    clearBathroomsMax: true,
                                    furnishedOnly: false,
                                    servicedOnly: false,
                                    clearLandSizeMin: true,
                                    clearLandSizeMax: true,
                                    titleDocumentType: '',
                                    city: '',
                                    area: '',
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
