import 'package:flutter/material.dart';
import '../constants/ng_states.dart';
import '../services/category_service.dart';
import '../ui/components/ft_components.dart';

class MarketplaceFiltersScreen extends StatefulWidget {
  final List<String> categories;
  final String selectedCategory;
  final int? selectedCategoryId;
  final int? selectedParentCategoryId;
  final int? selectedBrandId;
  final int? selectedModelId;
  final String initialQuery;
  final double? initialMinPrice;
  final double? initialMaxPrice;
  final String initialState;

  const MarketplaceFiltersScreen({
    super.key,
    required this.categories,
    required this.selectedCategory,
    this.selectedCategoryId,
    this.selectedParentCategoryId,
    this.selectedBrandId,
    this.selectedModelId,
    required this.initialQuery,
    this.initialState = allNigeriaLabel,
    this.initialMinPrice,
    this.initialMaxPrice,
  });

  @override
  State<MarketplaceFiltersScreen> createState() =>
      _MarketplaceFiltersScreenState();
}

class _MarketplaceFiltersScreenState extends State<MarketplaceFiltersScreen> {
  final _categorySvc = CategoryService();
  late final TextEditingController _queryCtrl;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late String _category;
  late String _state;
  int? _parentCategoryId;
  int? _categoryId;
  int? _brandId;
  int? _modelId;
  List<Map<String, dynamic>> _taxonomy = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _brands = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _models = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _queryCtrl = TextEditingController(text: widget.initialQuery);
    _minCtrl = TextEditingController(
      text: widget.initialMinPrice == null
          ? ''
          : widget.initialMinPrice!.toStringAsFixed(0),
    );
    _maxCtrl = TextEditingController(
      text: widget.initialMaxPrice == null
          ? ''
          : widget.initialMaxPrice!.toStringAsFixed(0),
    );
    _category = widget.selectedCategory;
    _state = widget.initialState;
    _parentCategoryId = widget.selectedParentCategoryId;
    _categoryId = widget.selectedCategoryId;
    _brandId = widget.selectedBrandId;
    _modelId = widget.selectedModelId;
    _loadTaxonomy();
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
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
              .map((entry) => Map<String, dynamic>.from(entry))
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

  List<Map<String, dynamic>> _leafForParent(int? parentId) {
    if (parentId == null) return const <Map<String, dynamic>>[];
    return _taxonomy
        .where((row) => int.tryParse('${row['parent_id'] ?? ''}') == parentId)
        .toList(growable: false);
  }

  Future<void> _loadTaxonomy() async {
    final tree = await _categorySvc.categoriesTree();
    final flat = _flattenCategories(tree);
    if (!mounted) return;
    setState(() => _taxonomy = flat);
    await _loadFilters();
  }

  Future<void> _loadFilters() async {
    final data = await _categorySvc.filters(
      categoryId: _categoryId ?? _parentCategoryId,
      brandId: _brandId,
    );
    if (!mounted) return;
    setState(() {
      _brands = data['brands'] ?? const <Map<String, dynamic>>[];
      _models = data['models'] ?? const <Map<String, dynamic>>[];
      if (_brandId != null &&
          !_brands.any((row) => int.tryParse('${row['id']}') == _brandId)) {
        _brandId = null;
      }
      if (_modelId != null &&
          !_models.any((row) => int.tryParse('${row['id']}') == _modelId)) {
        _modelId = null;
      }
    });
  }

  double? _toDouble(String value) {
    final t = value.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  void _apply() {
    final minPrice = _toDouble(_minCtrl.text);
    final maxPrice = _toDouble(_maxCtrl.text);
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Min price cannot be greater than max price.')),
      );
      return;
    }
    Navigator.pop(context, {
      'query': _queryCtrl.text.trim(),
      'category': _category,
      'parentCategoryId': _parentCategoryId,
      'categoryId': _categoryId,
      'brandId': _brandId,
      'modelId': _modelId,
      'state': _state,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
    });
  }

  void _clear() {
    setState(() {
      _queryCtrl.clear();
      _minCtrl.clear();
      _maxCtrl.clear();
      _category = 'All';
      _parentCategoryId = null;
      _categoryId = null;
      _brandId = null;
      _modelId = null;
      _state = allNigeriaLabel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Marketplace Filters',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _queryCtrl,
            decoration: const InputDecoration(
              labelText: 'Search text',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (_topCategories().isNotEmpty) ...[
            DropdownButtonFormField<int>(
              initialValue: _parentCategoryId,
              items: _topCategories()
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: int.tryParse('${row['id']}'),
                      child: Text((row['name'] ?? '').toString()),
                    ),
                  )
                  .toList(growable: false),
              decoration: const InputDecoration(
                labelText: 'Category group',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) async {
                setState(() {
                  _parentCategoryId = value;
                  _categoryId = null;
                  _brandId = null;
                  _modelId = null;
                });
                await _loadFilters();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              items: _leafForParent(_parentCategoryId)
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: int.tryParse('${row['id']}'),
                      child: Text((row['name'] ?? '').toString()),
                    ),
                  )
                  .toList(growable: false),
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) async {
                if (value == null) return;
                final row = _leafForParent(_parentCategoryId).firstWhere(
                  (entry) => int.tryParse('${entry['id']}') == value,
                  orElse: () => const <String, dynamic>{},
                );
                setState(() {
                  _categoryId = value;
                  _category = (row['name'] ?? _category).toString();
                  _brandId = null;
                  _modelId = null;
                });
                await _loadFilters();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _brandId,
              items: _brands
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: int.tryParse('${row['id']}'),
                      child: Text((row['name'] ?? '').toString()),
                    ),
                  )
                  .toList(growable: false),
              decoration: const InputDecoration(
                labelText: 'Brand (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) async {
                setState(() {
                  _brandId = value;
                  _modelId = null;
                });
                await _loadFilters();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _modelId,
              items: _models
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: int.tryParse('${row['id']}'),
                      child: Text((row['name'] ?? '').toString()),
                    ),
                  )
                  .toList(growable: false),
              decoration: const InputDecoration(
                labelText: 'Model (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _modelId = value),
            ),
          ] else
            DropdownButtonFormField<String>(
              value: _category,
              items: widget.categories
                  .map(
                      (c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                  .toList(),
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _category = v);
              },
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _state,
            items: <String>[allNigeriaLabel, ...nigeriaStates]
                .map((s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(displayState(s)),
                    ))
                .toList(),
            decoration: const InputDecoration(
              labelText: 'State',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _state = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Min price (₦)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Max price (₦)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FTSecondaryButton(
                  label: 'Clear',
                  onPressed: _clear,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FTPrimaryButton(
                  label: 'Apply',
                  onPressed: _apply,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
