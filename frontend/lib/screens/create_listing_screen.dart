import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/ng_states.dart';
import '../services/api_service.dart';
import '../services/auth_gate_service.dart';
import '../services/api_client.dart';
import '../services/category_service.dart';
import '../services/feed_service.dart';
import '../services/listing_service.dart';
import '../services/marketplace_catalog_service.dart';
import '../services/pricing_service.dart';
import '../services/analytics_hooks.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/role_gates.dart';
import '../widgets/phone_verification_dialog.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  static const _legacyDraftKey = 'create_listing_draft_v2';
  static const _draftsKey = 'create_listing_drafts_v3';
  static const _lastDraftBucketKey = 'create_listing_last_bucket_v3';
  static const _lastCategoryKey = 'create_listing_last_category_id_v1';

  final _listingService = ListingService();
  final _feedService = FeedService();
  final _catalog = MarketplaceCatalogService();
  final _categorySvc = CategoryService();
  final _pricingService = PricingService();

  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _localityCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();
  final _categorySearchCtrl = TextEditingController();

  int _step = 0;
  bool _loading = false;
  bool _loadingLocations = false;
  bool _showValidation = false;
  bool _inspectionEnabled = true;
  bool _deliveryEnabled = true;
  bool _loadingSuggestions = false;
  bool _suggestingPrice = false;

  String _category = 'General';
  int? _parentCategoryId;
  int? _categoryId;
  int? _brandId;
  int? _modelId;
  String _condition = 'Used - Good';
  String _state = 'Lagos';

  List<String> _states = const [];
  Map<String, List<String>> _citiesByState = const {};
  Map<String, List<String>> _majorCities = const {};
  List<Map<String, dynamic>> _taxonomy = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _brandOptions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _modelOptions = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _categorySuggestions =
      const <Map<String, dynamic>>[];

  List<Map<String, dynamic>> _dynamicFields = const <Map<String, dynamic>>[];
  String _metadataKey = '';
  String _listingTypeHint = 'declutter';
  bool _loadingSchema = false;
  final Map<String, TextEditingController> _metaTextCtrls =
      <String, TextEditingController>{};
  final Map<String, String> _metaSelectValues = <String, String>{};
  final Map<String, bool> _metaBoolValues = <String, bool>{};
  Map<String, dynamic> _pendingMetadataValues = const <String, dynamic>{};

  File? _selectedImage;
  String? _selectedImagePath;
  Timer? _titleDebounce;
  List<String> _titleSuggestions = const <String>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final granted = await requireAuthForAction(
        context,
        action: 'create a listing',
        onAuthorized: () async {},
      );
      if (!granted && mounted) {
        Navigator.of(context).maybePop();
      }
    });
    _attachDraftListeners();
    _titleCtrl.addListener(_onTitleChanged);
    _categorySearchCtrl.addListener(_onCategorySearchChanged);
    _loadDraft().then((_) async {
      await _loadLocations();
      await _loadTaxonomy();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    _cityCtrl.dispose();
    _localityCtrl.dispose();
    _lgaCtrl.dispose();
    _categorySearchCtrl.dispose();
    for (final ctrl in _metaTextCtrls.values) {
      ctrl.dispose();
    }
    _titleDebounce?.cancel();
    super.dispose();
  }

  void _attachDraftListeners() {
    _titleCtrl.addListener(_saveDraft);
    _priceCtrl.addListener(_saveDraft);
    _descCtrl.addListener(_saveDraft);
    _cityCtrl.addListener(_saveDraft);
    _localityCtrl.addListener(_saveDraft);
    _lgaCtrl.addListener(_saveDraft);
  }

  void _onTitleChanged() {
    _titleDebounce?.cancel();
    _titleDebounce = Timer(const Duration(milliseconds: 280), () async {
      final q = _titleCtrl.text.trim();
      if (q.length < 2) {
        if (!mounted) return;
        setState(() {
          _loadingSuggestions = false;
          _titleSuggestions = const <String>[];
        });
        return;
      }
      if (!mounted) return;
      setState(() => _loadingSuggestions = true);
      final values = await _catalog.titleSuggestions(q, limit: 8);
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _titleSuggestions = values;
      });
    });
  }

  void _onCategorySearchChanged() {
    final q = _categorySearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() => _categorySuggestions = const <Map<String, dynamic>>[]);
      return;
    }
    final rows = _taxonomy
        .where(
            (row) => (row['name'] ?? '').toString().toLowerCase().contains(q))
        .take(8)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    if (!mounted) return;
    setState(() => _categorySuggestions = rows);
  }

  Map<String, dynamic>? _categoryById(int? categoryId) {
    if (categoryId == null) return null;
    for (final row in _taxonomy) {
      final rowId = int.tryParse('${row['id'] ?? ''}');
      if (rowId == categoryId) {
        return row;
      }
    }
    return null;
  }

  void _disposeSchemaControllers() {
    for (final ctrl in _metaTextCtrls.values) {
      ctrl.dispose();
    }
    _metaTextCtrls.clear();
    _metaSelectValues.clear();
    _metaBoolValues.clear();
  }

  void _applyPendingMetadataValues() {
    if (_pendingMetadataValues.isEmpty) return;
    final values = Map<String, dynamic>.from(_pendingMetadataValues);
    for (final entry in values.entries) {
      final key = entry.key;
      final rawValue = entry.value;
      final textCtrl = _metaTextCtrls[key];
      if (textCtrl != null) {
        textCtrl.text = '$rawValue';
        continue;
      }
      if (_metaSelectValues.containsKey(key)) {
        _metaSelectValues[key] = '$rawValue';
        continue;
      }
      if (_metaBoolValues.containsKey(key)) {
        _metaBoolValues[key] = rawValue == true ||
            '$rawValue'.toLowerCase() == 'true' ||
            '$rawValue' == '1';
      }
    }
    _pendingMetadataValues = const <String, dynamic>{};
  }

  void _rebuildSchemaControllers(List<Map<String, dynamic>> fields) {
    _disposeSchemaControllers();
    for (final field in fields) {
      final key = (field['key'] ?? '').toString();
      final type = (field['type'] ?? 'text').toString();
      if (key.isEmpty) continue;
      if (type == 'select') {
        _metaSelectValues[key] = '';
      } else if (type == 'boolean') {
        _metaBoolValues[key] = false;
      } else {
        _metaTextCtrls[key] = TextEditingController();
      }
    }
  }

  Future<void> _loadDynamicSchema() async {
    final selectedCategory = _categoryId ?? _parentCategoryId;
    if (selectedCategory == null) {
      if (!mounted) return;
      setState(() {
        _dynamicFields = const <Map<String, dynamic>>[];
        _metadataKey = '';
        _listingTypeHint = 'declutter';
      });
      _disposeSchemaControllers();
      return;
    }

    final carryValues = _collectMetadataValues();
    if (_pendingMetadataValues.isEmpty && carryValues.isNotEmpty) {
      _pendingMetadataValues = carryValues;
    }

    if (mounted) setState(() => _loadingSchema = true);
    final payload = await _categorySvc.formSchema(
      categoryId: selectedCategory,
      category: _category,
    );
    if (!mounted) return;
    final schema = payload['schema'] is Map
        ? Map<String, dynamic>.from(payload['schema'] as Map)
        : const <String, dynamic>{};
    final fields = (schema['fields'] is List)
        ? (schema['fields'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    _rebuildSchemaControllers(fields);
    _applyPendingMetadataValues();
    setState(() {
      _dynamicFields = fields;
      _metadataKey = (schema['metadata_key'] ?? '').toString();
      _listingTypeHint =
          (schema['listing_type_hint'] ?? 'declutter').toString();
      _loadingSchema = false;
    });
  }

  Future<void> _selectCategoryFromSuggestion(Map<String, dynamic> row) async {
    final rowId = int.tryParse('${row['id'] ?? ''}');
    final parentId = int.tryParse('${row['parent_id'] ?? ''}');
    if (rowId == null) return;

    final oldBucket = _draftBucket();
    await _saveDraft();

    if (parentId == null) {
      setState(() {
        _parentCategoryId = rowId;
        _categoryId = null;
        _category = (row['name'] ?? _category).toString();
        _categorySearchCtrl.text = (row['name'] ?? '').toString();
        _brandId = null;
        _modelId = null;
        _categorySuggestions = const <Map<String, dynamic>>[];
      });
    } else {
      setState(() {
        _parentCategoryId = parentId;
        _categoryId = rowId;
        _category = (row['name'] ?? _category).toString();
        _categorySearchCtrl.text = (row['name'] ?? '').toString();
        _brandId = null;
        _modelId = null;
        _categorySuggestions = const <Map<String, dynamic>>[];
      });
    }

    final newBucket = _draftBucket();
    if (newBucket != oldBucket) {
      await _loadDraft(bucket: newBucket);
    }
    await _loadBrandModelOptions();
    await _loadDynamicSchema();
    await _saveDraft();
  }

  List<String> _missingRequiredDynamicFields() {
    final missing = <String>[];
    for (final field in _dynamicFields) {
      if (field['required'] != true) continue;
      final key = (field['key'] ?? '').toString();
      final label = (field['label'] ?? key).toString();
      final type = (field['type'] ?? 'text').toString();
      if (key.isEmpty) continue;
      if (type == 'select') {
        final value = (_metaSelectValues[key] ?? '').trim();
        if (value.isEmpty) {
          missing.add(label);
        }
      } else if (type == 'boolean') {
        if (!_metaBoolValues.containsKey(key)) {
          missing.add(label);
        }
      } else {
        final value = (_metaTextCtrls[key]?.text ?? '').trim();
        if (value.isEmpty) {
          missing.add(label);
        }
      }
    }
    return missing;
  }

  Map<String, dynamic> _buildMetadataPayload() {
    final payload = <String, dynamic>{};
    for (final field in _dynamicFields) {
      final key = (field['key'] ?? '').toString();
      final type = (field['type'] ?? 'text').toString();
      if (key.isEmpty) continue;
      if (type == 'select') {
        final value = (_metaSelectValues[key] ?? '').trim();
        if (value.isNotEmpty) {
          payload[key] = value;
        }
        continue;
      }
      if (type == 'boolean') {
        if (_metaBoolValues.containsKey(key)) {
          payload[key] = _metaBoolValues[key] == true;
        }
        continue;
      }
      final rawValue = (_metaTextCtrls[key]?.text ?? '').trim();
      if (rawValue.isEmpty) continue;
      if (type == 'number') {
        final asInt = int.tryParse(rawValue);
        if (asInt != null) {
          payload[key] = asInt;
          continue;
        }
        final asDouble = double.tryParse(rawValue);
        if (asDouble != null) {
          payload[key] = asDouble;
          continue;
        }
      }
      payload[key] = rawValue;
    }
    return payload;
  }

  bool _isDynamicFieldMissing(Map<String, dynamic> field) {
    if (field['required'] != true) return false;
    final key = (field['key'] ?? '').toString();
    final type = (field['type'] ?? 'text').toString();
    if (key.isEmpty) return false;
    if (type == 'select') {
      return (_metaSelectValues[key] ?? '').trim().isEmpty;
    }
    if (type == 'boolean') {
      return !_metaBoolValues.containsKey(key);
    }
    return (_metaTextCtrls[key]?.text ?? '').trim().isEmpty;
  }

  Widget _buildDynamicField(Map<String, dynamic> field) {
    final key = (field['key'] ?? '').toString();
    final label = (field['label'] ?? key).toString();
    final type = (field['type'] ?? 'text').toString();
    final options = (field['options'] is List)
        ? (field['options'] as List)
            .map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final required = field['required'] == true;

    if (type == 'select') {
      final selected = (_metaSelectValues[key] ?? '').trim();
      final selectedOrNull =
          options.contains(selected) && selected.isNotEmpty ? selected : null;
      return DropdownButtonFormField<String>(
        value: selectedOrNull,
        items: options
            .map((item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                ))
            .toList(growable: false),
        onChanged: (value) async {
          setState(() => _metaSelectValues[key] = (value ?? '').trim());
          await _saveDraft();
        },
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          border: const OutlineInputBorder(),
          errorText: _showValidation && _isDynamicFieldMissing(field)
              ? '$label is required'
              : null,
        ),
      );
    }

    if (type == 'boolean') {
      final current = _metaBoolValues[key] == true;
      return SwitchListTile.adaptive(
        value: current,
        onChanged: (value) async {
          setState(() => _metaBoolValues[key] = value);
          await _saveDraft();
        },
        title: Text(required ? '$label *' : label),
        contentPadding: EdgeInsets.zero,
      );
    }

    final ctrl = _metaTextCtrls[key] ??= TextEditingController();
    return TextField(
      controller: ctrl,
      keyboardType: type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) => _saveDraft(),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        border: const OutlineInputBorder(),
        errorText: _showValidation && _isDynamicFieldMissing(field)
            ? '$label is required'
            : null,
      ),
    );
  }

  String _draftBucket({int? parentCategoryId}) {
    final id = parentCategoryId ?? _parentCategoryId ?? 0;
    return 'group_$id';
  }

  Map<String, dynamic> _collectMetadataValues() {
    final out = <String, dynamic>{};
    for (final entry in _metaTextCtrls.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        out[entry.key] = value;
      }
    }
    for (final entry in _metaSelectValues.entries) {
      final value = entry.value.trim();
      if (value.isNotEmpty) {
        out[entry.key] = value;
      }
    }
    for (final entry in _metaBoolValues.entries) {
      out[entry.key] = entry.value;
    }
    return out;
  }

  Future<Map<String, dynamic>> _readDraftStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftsKey);
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _loadDraft({String? bucket}) async {
    final prefs = await SharedPreferences.getInstance();
    final draftStore = await _readDraftStore();
    final activeBucket =
        bucket ?? prefs.getString(_lastDraftBucketKey) ?? _draftBucket();
    Map<String, dynamic>? draft;

    final picked = draftStore[activeBucket];
    if (picked is Map) {
      draft = Map<String, dynamic>.from(picked);
    }

    if (draft == null) {
      final legacy = prefs.getString(_legacyDraftKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(legacy);
          if (decoded is Map) {
            draft = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    if (draft == null) return;

    _titleCtrl.text = (draft['title'] ?? '').toString();
    _priceCtrl.text = (draft['price'] ?? '').toString();
    _descCtrl.text = (draft['description'] ?? '').toString();
    _cityCtrl.text = (draft['city'] ?? '').toString();
    _localityCtrl.text = (draft['locality'] ?? '').toString();
    _lgaCtrl.text = (draft['lga'] ?? '').toString();
    _category = (draft['category'] ?? _category).toString();
    _parentCategoryId =
        int.tryParse((draft['parent_category_id'] ?? '').toString());
    _categoryId = int.tryParse((draft['category_id'] ?? '').toString());
    _brandId = int.tryParse((draft['brand_id'] ?? '').toString());
    _modelId = int.tryParse((draft['model_id'] ?? '').toString());
    _condition = (draft['condition'] ?? _condition).toString();
    _state = (draft['state'] ?? _state).toString();
    _inspectionEnabled = draft['inspection_enabled'] == true;
    _deliveryEnabled = draft['delivery_enabled'] != false;
    _step = int.tryParse((draft['step'] ?? 0).toString()) ?? 0;
    _selectedImagePath = (draft['image_path'] ?? '').toString();
    _listingTypeHint =
        (draft['listing_type_hint'] ?? _listingTypeHint).toString();

    final metadataRaw = draft['metadata_values'];
    if (metadataRaw is Map) {
      _pendingMetadataValues = Map<String, dynamic>.from(metadataRaw);
    }

    if (_selectedImagePath != null &&
        _selectedImagePath!.trim().isNotEmpty &&
        File(_selectedImagePath!).existsSync()) {
      _selectedImage = File(_selectedImagePath!);
    }

    if (_categoryId != null) {
      await prefs.setString(_lastCategoryKey, '$_categoryId');
    }
    await prefs.setString(_lastDraftBucketKey, activeBucket);
    if (mounted) setState(() {});
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftStore = await _readDraftStore();
    final bucket = _draftBucket();

    final payload = <String, dynamic>{
      'step': _step,
      'title': _titleCtrl.text.trim(),
      'price': _priceCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'locality': _localityCtrl.text.trim(),
      'lga': _lgaCtrl.text.trim(),
      'category': _category,
      'parent_category_id': _parentCategoryId,
      'category_id': _categoryId,
      'brand_id': _brandId,
      'model_id': _modelId,
      'condition': _condition,
      'state': _state,
      'inspection_enabled': _inspectionEnabled,
      'delivery_enabled': _deliveryEnabled,
      'listing_type_hint': _listingTypeHint,
      'metadata_values': _collectMetadataValues(),
      'image_path': _selectedImagePath ?? _selectedImage?.path ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    };

    draftStore[bucket] = payload;
    await prefs.setString(_draftsKey, jsonEncode(draftStore));
    await prefs.setString(_lastDraftBucketKey, bucket);
    if (_categoryId != null) {
      await prefs.setString(_lastCategoryKey, '$_categoryId');
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final draftStore = await _readDraftStore();
    draftStore.remove(_draftBucket());
    await prefs.setString(_draftsKey, jsonEncode(draftStore));
    await prefs.remove(_legacyDraftKey);
  }

  Future<void> _loadLocations() async {
    if (_loadingLocations) return;
    setState(() => _loadingLocations = true);
    try {
      final res = await _feedService.getLocations();

      final states = (res['states'] is List)
          ? (res['states'] as List).map((e) => e.toString()).toList()
          : <String>[];

      final cbs = <String, List<String>>{};
      if (res['cities_by_state'] is Map) {
        (res['cities_by_state'] as Map).forEach((k, v) {
          if (v is List) {
            cbs[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }

      final majors = <String, List<String>>{};
      if (res['major_cities'] is Map) {
        (res['major_cities'] as Map).forEach((k, v) {
          if (v is List) {
            majors[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }

      if (!mounted) return;
      setState(() {
        _states = states;
        _citiesByState = cbs;
        _majorCities = majors;
        if (_states.isNotEmpty && !_states.contains(_state)) {
          _state = _states.first;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
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
        .where((row) =>
            int.tryParse('${row['parent_id'] ?? ''}') == int.parse('$parentId'))
        .toList(growable: false);
  }

  Future<void> _loadTaxonomy() async {
    final tree = await _categorySvc.categoriesTree();
    final prefs = await SharedPreferences.getInstance();
    final lastCategoryId =
        int.tryParse(prefs.getString(_lastCategoryKey) ?? '');
    if (!mounted) return;
    final flat = _flattenCategories(tree);
    int? nextParent = _parentCategoryId;
    int? nextCategory = _categoryId;
    String nextCategoryName = _category;

    if (nextCategory == null && lastCategoryId != null) {
      for (final row in flat) {
        final rowId = int.tryParse('${row['id'] ?? ''}');
        if (rowId == lastCategoryId) {
          nextCategory = rowId;
          nextParent = int.tryParse('${row['parent_id'] ?? ''}');
          nextCategoryName = (row['name'] ?? _category).toString();
          break;
        }
      }
    }

    setState(() {
      _taxonomy = flat;
      _parentCategoryId = nextParent;
      _categoryId = nextCategory;
      _category = nextCategoryName;
    });
    await _loadBrandModelOptions();
    await _loadDynamicSchema();
  }

  Future<void> _loadBrandModelOptions() async {
    final selectedCategory = _categoryId ?? _parentCategoryId;
    final data = await _categorySvc.filters(
      categoryId: selectedCategory,
      brandId: _brandId,
    );
    if (!mounted) return;
    setState(() {
      _brandOptions = data['brands'] ?? const <Map<String, dynamic>>[];
      _modelOptions = data['models'] ?? const <Map<String, dynamic>>[];
      if (_brandId != null &&
          !_brandOptions
              .any((row) => int.tryParse('${row['id']}') == _brandId)) {
        _brandId = null;
      }
      if (_modelId != null &&
          !_modelOptions
              .any((row) => int.tryParse('${row['id']}') == _modelId)) {
        _modelId = null;
      }
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    final image = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1400,
    );
    if (!mounted || image == null) return;
    setState(() {
      _selectedImage = File(image.path);
      _selectedImagePath = image.path;
    });
    await _saveDraft();
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0:
        if (_categoryId == null && _category.trim().isEmpty) {
          _showSnack('Select a category.');
          setState(() => _showValidation = true);
          return false;
        }
        setState(() => _showValidation = false);
        return true;
      case 1:
        final title = _titleCtrl.text.trim();
        final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
        final missingDynamic = _missingRequiredDynamicFields();
        if (title.isEmpty) {
          _showSnack('Listing title is required.');
          setState(() => _showValidation = true);
          return false;
        }
        if (price <= 0) {
          _showSnack('Enter a valid price.');
          setState(() => _showValidation = true);
          return false;
        }
        if (missingDynamic.isNotEmpty) {
          _showSnack('Complete required category fields.');
          setState(() => _showValidation = true);
          return false;
        }
        setState(() => _showValidation = false);
        return true;
      case 2:
        if (_selectedImage == null) {
          _showSnack('Add at least one photo to continue.');
          setState(() => _showValidation = true);
          return false;
        }
        setState(() => _showValidation = false);
        return true;
      default:
        setState(() => _showValidation = false);
        return true;
    }
  }

  bool _isStepComplete(int index) {
    switch (index) {
      case 0:
        return _categoryId != null || _category.trim().isNotEmpty;
      case 1:
        return _titleCtrl.text.trim().isNotEmpty &&
            (double.tryParse(_priceCtrl.text.trim()) ?? 0) > 0 &&
            _missingRequiredDynamicFields().isEmpty;
      case 2:
        return _selectedImage != null;
      case 3:
        return true;
      case 4:
        return _titleCtrl.text.trim().isNotEmpty &&
            (double.tryParse(_priceCtrl.text.trim()) ?? 0) > 0 &&
            _selectedImage != null &&
            _missingRequiredDynamicFields().isEmpty;
      default:
        return false;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  int _priceMinorFromInput() {
    final parsed = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
    return (parsed * 100).round();
  }

  Future<void> _openPriceSuggestion() async {
    if (_suggestingPrice) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _showSnack('Enter a title first to get a useful suggestion.');
      return;
    }
    setState(() => _suggestingPrice = true);
    try {
      final payload = await _pricingService.suggest(
        category: 'declutter',
        city: _cityCtrl.text.trim().isNotEmpty ? _cityCtrl.text.trim() : _state,
        itemType: title,
        condition: _condition,
        currentPriceMinor: _priceMinorFromInput(),
      );
      if (!mounted) return;
      if (payload['ok'] != true) {
        _showSnack(
            (payload['message'] ?? 'Could not fetch suggestion').toString());
        return;
      }
      final suggestedMinor =
          int.tryParse('${payload['suggested_price_minor'] ?? 0}') ?? 0;
      final rangeMap = payload['range_minor'] is Map
          ? Map<String, dynamic>.from(payload['range_minor'] as Map)
          : const <String, dynamic>{};
      final lowMinor = int.tryParse('${rangeMap['low'] ?? 0}') ?? 0;
      final highMinor = int.tryParse('${rangeMap['high'] ?? 0}') ?? 0;
      final explanation = (payload['explanation'] is List)
          ? (payload['explanation'] as List)
              .map((row) => row.toString())
              .toList(growable: false)
          : const <String>[];

      final apply = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Price Suggestion',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatNaira(suggestedMinor / 100),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Recommended range: ${formatNaira(lowMinor / 100)} - ${formatNaira(highMinor / 100)}',
                  ),
                  const SizedBox(height: 4),
                  Text('Confidence: ${(payload['confidence'] ?? 'low')}'),
                  const SizedBox(height: 10),
                  ...explanation.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $line'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FTButton(
                          label: 'Apply suggestion',
                          icon: Icons.check_circle_outline,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FTButton(
                          label: 'Keep current',
                          variant: FTButtonVariant.ghost,
                          onPressed: () => Navigator.of(context).pop(false),
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

      if (apply == true && suggestedMinor > 0 && mounted) {
        _priceCtrl.text = (suggestedMinor / 100).toStringAsFixed(0);
        await _saveDraft();
        if (!mounted) return;
        _showSnack('Suggestion applied.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not fetch suggestion right now.');
    } finally {
      if (mounted) {
        setState(() => _suggestingPrice = false);
      }
    }
  }

  Future<void> _showDuplicateImageDialog(Map<String, dynamic> response) async {
    final supportCode = (response['trace_id'] ??
            response['request_id'] ??
            ApiClient.instance.lastFailedRequestId ??
            '')
        .toString()
        .trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Photo Already Used'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('This photo has already been used on FlipTrybe.'),
              const SizedBox(height: 8),
              const Text('Choose a different photo to continue.'),
              if (supportCode.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Support code: $supportCode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Choose a different photo'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    setState(() => _step = 2);
  }

  Future<void> _submitListing() async {
    if (_loading) return;
    final profile = await ApiService.getProfile();
    if (!mounted) return;
    final block = RoleGates.forPostListing(profile);
    final allowed = await guardRestrictedAction(
      context,
      block: block,
      authAction: 'create a listing',
      onAllowed: () async {},
    );
    if (!allowed) return;
    if (!_validateCurrentStep()) return;

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;

    if (title.isEmpty || price <= 0 || _selectedImage == null) {
      _showSnack('Complete all required fields before publishing.');
      return;
    }

    final metadataPayload = _buildMetadataPayload();
    Map<String, dynamic>? vehicleMetadata;
    Map<String, dynamic>? energyMetadata;
    if (_metadataKey == 'vehicle_metadata' && metadataPayload.isNotEmpty) {
      vehicleMetadata = metadataPayload;
    }
    if (_metadataKey == 'energy_metadata' && metadataPayload.isNotEmpty) {
      energyMetadata = metadataPayload;
    }

    setState(() => _loading = true);
    final res = await _listingService.createListing(
      title: title,
      description: [
        desc,
        'Category: $_category',
        'Condition: $_condition',
        'State: $_state',
        if (_cityCtrl.text.trim().isNotEmpty) 'City: ${_cityCtrl.text.trim()}',
        if (_localityCtrl.text.trim().isNotEmpty)
          'Locality: ${_localityCtrl.text.trim()}',
        if (_lgaCtrl.text.trim().isNotEmpty) 'LGA: ${_lgaCtrl.text.trim()}',
      ].where((line) => line.trim().isNotEmpty).join('\n'),
      price: price,
      listingType: _listingTypeHint,
      vehicleMetadata: vehicleMetadata,
      energyMetadata: energyMetadata,
      category: _category,
      categoryId: _categoryId,
      brandId: _brandId,
      modelId: _modelId,
      state: _state,
      city: _cityCtrl.text.trim(),
      locality: _localityCtrl.text.trim(),
      deliveryAvailable: _deliveryEnabled,
      inspectionRequired: _inspectionEnabled,
      imagePath: _selectedImage!.path,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    final ok = res['ok'] == true;
    final code = (res['code'] ?? '').toString().trim().toUpperCase();
    final msg = (res['message'] ?? res['error'] ?? 'Failed to publish listing')
        .toString();

    if (!ok && ApiService.isPhoneNotVerified(res)) {
      await showPhoneVerificationRequiredDialog(
        context,
        message: msg,
        onRetry: _submitListing,
      );
      return;
    }

    if (ok) {
      await AnalyticsHooks.instance.track(
        'listing_created',
        properties: <String, Object?>{
          'category': _category,
          'category_id': _categoryId,
          'brand_id': _brandId,
        },
      );
      await _clearDraft();
      if (!mounted) return;
      _showSnack('Listing published successfully.');
      Navigator.of(context).pop();
      return;
    }

    if (code.startsWith('DUPLICATE_IMAGE')) {
      await _showDuplicateImageDialog(res);
      return;
    }

    _showSnack(msg);
  }

  List<String> _stateItems() {
    if (_states.isNotEmpty) return _states;
    return nigeriaStates;
  }

  @override
  Widget build(BuildContext context) {
    final cities = _citiesByState[_state] ?? const <String>[];
    final majorCities = _majorCities[_state] ?? const <String>[];
    final cityChips = cities.isNotEmpty ? cities : majorCities;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Listing'),
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : () async {
                    await _clearDraft();
                    if (!mounted) return;
                    _showSnack('Draft cleared.');
                    setState(() {
                      _step = 0;
                      _titleCtrl.clear();
                      _priceCtrl.clear();
                      _descCtrl.clear();
                      _cityCtrl.clear();
                      _localityCtrl.clear();
                      _lgaCtrl.clear();
                      _categorySearchCtrl.clear();
                      _selectedImage = null;
                      _selectedImagePath = null;
                      _category = 'General';
                      _parentCategoryId = null;
                      _categoryId = null;
                      _brandId = null;
                      _modelId = null;
                      _condition = 'Used - Good';
                      _inspectionEnabled = true;
                      _deliveryEnabled = true;
                      _dynamicFields = const <Map<String, dynamic>>[];
                      _metadataKey = '';
                      _listingTypeHint = 'declutter';
                      _pendingMetadataValues = const <String, dynamic>{};
                    });
                    _disposeSchemaControllers();
                  },
            child: const Text('Clear draft'),
          ),
        ],
      ),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (value) => setState(() => _step = value),
        controlsBuilder: (context, details) {
          final isLast = _step == 4;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: FTAsyncButton(
                    label: isLast ? 'Publish listing' : 'Continue',
                    variant: FTButtonVariant.primary,
                    externalLoading: _loading,
                    onPressed: _loading
                        ? null
                        : () async {
                            if (isLast) {
                              await _submitListing();
                              return;
                            }
                            if (!_validateCurrentStep()) return;
                            setState(() => _step = (_step + 1).clamp(0, 4));
                            await _saveDraft();
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTButton(
                    variant: FTButtonVariant.ghost,
                    label: _step == 0 ? 'Cancel' : 'Back',
                    onPressed: _loading
                        ? null
                        : () async {
                            if (_step == 0) {
                              Navigator.of(context).pop();
                              return;
                            }
                            setState(() => _step = (_step - 1).clamp(0, 4));
                            await _saveDraft();
                          },
                  ),
                ),
              ],
            ),
          );
        },
        steps: [
          Step(
            title: const Text('Category'),
            subtitle: const Text('Set category and listing location'),
            isActive: _step >= 0,
            state: _isStepComplete(0) ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_topCategories().isNotEmpty) ...[
                  TextField(
                    controller: _categorySearchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search category',
                      hintText: 'Cars, Inverters, Solar Bundle...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_categorySuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _categorySuggestions.map((row) {
                          final label = (row['name'] ?? '').toString();
                          return ActionChip(
                            label: Text(label),
                            onPressed: () => _selectCategoryFromSuggestion(row),
                          );
                        }).toList(growable: false),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
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
                    onChanged: (value) async {
                      final oldBucket = _draftBucket();
                      await _saveDraft();
                      setState(() {
                        _parentCategoryId = value;
                        _categoryId = null;
                        _brandId = null;
                        _modelId = null;
                        final row = _categoryById(value);
                        if (row != null) {
                          _category = (row['name'] ?? _category).toString();
                        }
                      });
                      final newBucket = _draftBucket();
                      if (newBucket != oldBucket) {
                        await _loadDraft(bucket: newBucket);
                      }
                      await _loadBrandModelOptions();
                      await _loadDynamicSchema();
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category group',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _categoryId,
                    items: _leafCategoriesForParent(_parentCategoryId)
                        .map(
                          (row) => DropdownMenuItem<int>(
                            value: int.tryParse('${row['id']}'),
                            child: Text((row['name'] ?? '').toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) async {
                      if (value == null) return;
                      final oldBucket = _draftBucket();
                      await _saveDraft();
                      final row = _leafCategoriesForParent(_parentCategoryId)
                          .firstWhere(
                        (entry) => int.tryParse('${entry['id']}') == value,
                        orElse: () => const <String, dynamic>{},
                      );
                      setState(() {
                        _categoryId = value;
                        _category = (row['name'] ?? _category).toString();
                        _brandId = null;
                        _modelId = null;
                      });
                      final newBucket = _draftBucket();
                      if (newBucket != oldBucket) {
                        await _loadDraft(bucket: newBucket);
                      }
                      await _loadBrandModelOptions();
                      await _loadDynamicSchema();
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _brandId,
                    items: _brandOptions
                        .map(
                          (row) => DropdownMenuItem<int>(
                            value: int.tryParse('${row['id']}'),
                            child: Text((row['name'] ?? '').toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) async {
                      setState(() {
                        _brandId = value;
                        _modelId = null;
                      });
                      await _loadBrandModelOptions();
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Brand (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _modelId,
                    items: _modelOptions
                        .map(
                          (row) => DropdownMenuItem<int>(
                            value: int.tryParse('${row['id']}'),
                            child: Text((row['name'] ?? '').toString()),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) async {
                      setState(() => _modelId = value);
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Model (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    items: const ['General']
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                        _parentCategoryId = null;
                        _categoryId = null;
                      });
                      await _loadDynamicSchema();
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _state,
                  items: _stateItems()
                      .map((s) => DropdownMenuItem(
                          value: s, child: Text(displayState(s))))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _state = value);
                    await _saveDraft();
                  },
                  decoration: InputDecoration(
                    labelText:
                        _loadingLocations ? 'State (loading...)' : 'State',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'Ikeja, Yaba, Wuse, GRA...',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_showValidation &&
                    _category.trim().isEmpty &&
                    _categoryId == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Category is required.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                if (cityChips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: cityChips.take(12).map((city) {
                      return ActionChip(
                        label: Text(city),
                        onPressed: () async {
                          _cityCtrl.text = city;
                          await _saveDraft();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          Step(
            title: const Text('Basics'),
            subtitle: const Text('Title, price and condition'),
            isActive: _step >= 1,
            state: _isStepComplete(1) ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. iPhone 13 Pro Max',
                    border: const OutlineInputBorder(),
                    errorText: _showValidation && _titleCtrl.text.trim().isEmpty
                        ? 'Title is required'
                        : null,
                  ),
                ),
                if (_loadingSuggestions) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_titleSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _titleSuggestions.map((suggestion) {
                        return ActionChip(
                          label: Text(suggestion),
                          onPressed: () async {
                            _titleCtrl.text = suggestion;
                            _titleCtrl.selection = TextSelection.fromPosition(
                              TextPosition(offset: _titleCtrl.text.length),
                            );
                            setState(
                                () => _titleSuggestions = const <String>[]);
                            await _saveDraft();
                          },
                        );
                      }).toList(growable: false),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Price (₦)',
                    hintText: 'e.g. 450000',
                    border: const OutlineInputBorder(),
                    errorText: _showValidation &&
                            (double.tryParse(_priceCtrl.text.trim()) ?? 0) <= 0
                        ? 'Enter a valid price'
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FTButton(
                    label: _suggestingPrice
                        ? 'Calculating...'
                        : 'Get price suggestion',
                    icon: Icons.auto_graph_outlined,
                    variant: FTButtonVariant.ghost,
                    onPressed: _suggestingPrice ? null : _openPriceSuggestion,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _condition,
                  items: const [
                    'Brand New',
                    'Used - Like New',
                    'Used - Good',
                    'Used - Fair',
                  ]
                      .map((item) =>
                          DropdownMenuItem(value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => _condition = value);
                    await _saveDraft();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Condition',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText:
                        'Describe item condition, accessories, and defects.',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_loadingSchema) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (_dynamicFields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _metadataKey == 'vehicle_metadata'
                          ? 'Vehicle details'
                          : _metadataKey == 'energy_metadata'
                              ? 'Power & energy details'
                              : 'Category details',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ..._dynamicFields.map((field) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildDynamicField(field),
                    );
                  }).toList(growable: false),
                ],
              ],
            ),
          ),
          Step(
            title: const Text('Photos'),
            subtitle: const Text('Add at least one image'),
            isActive: _step >= 2,
            state: _isStepComplete(2) ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: _pickImage,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 210,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade400),
                      color: Colors.grey.shade50,
                      image: _selectedImage == null
                          ? null
                          : DecorationImage(
                              image: FileImage(_selectedImage!),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: _selectedImage == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_a_photo_outlined, size: 32),
                                SizedBox(height: 8),
                                Text('Tap to add photo'),
                              ],
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use clear photos. Listings with quality images convert better.',
                ),
                if (_showValidation && _selectedImage == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'At least one photo is required.',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          Step(
            title: const Text('Delivery Options'),
            subtitle: const Text('Set fulfillment preferences'),
            isActive: _step >= 3,
            state: _isStepComplete(3) ? StepState.complete : StepState.indexed,
            content: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _deliveryEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Delivery'),
                  subtitle:
                      const Text('Allow delivery requests for this listing'),
                  onChanged: (value) async {
                    setState(() => _deliveryEnabled = value);
                    await _saveDraft();
                  },
                ),
                SwitchListTile.adaptive(
                  value: _inspectionEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Optional Inspection'),
                  subtitle: const Text(
                      'Buyers can request inspection before delivery'),
                  onChanged: (value) async {
                    setState(() => _inspectionEnabled = value);
                    await _saveDraft();
                  },
                ),
                TextField(
                  controller: _localityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Locality / Area (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lgaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'LGA (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Preview & Publish'),
            subtitle: const Text('Review details before posting'),
            isActive: _step >= 4,
            state: _isStepComplete(4) ? StepState.complete : StepState.indexed,
            content: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedImage != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          _selectedImage!,
                          height: 170,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (_selectedImage != null) const SizedBox(height: 10),
                    Text(
                      _titleCtrl.text.trim().isEmpty
                          ? 'Untitled listing'
                          : _titleCtrl.text.trim(),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatNaira(double.tryParse(_priceCtrl.text.trim()) ?? 0),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const Divider(height: 18),
                    Text('Category: $_category'),
                    Text('Condition: $_condition'),
                    if (_listingTypeHint.trim().isNotEmpty &&
                        _listingTypeHint != 'declutter')
                      Text('Listing type: $_listingTypeHint'),
                    Text(
                        'Location: ${_cityCtrl.text.trim()}, ${displayState(_state)}'),
                    Text(
                        'Delivery: ${_deliveryEnabled ? 'Enabled' : 'Disabled'}'),
                    Text(
                        'Inspection: ${_inspectionEnabled ? 'Enabled' : 'Disabled'}'),
                    if (_dynamicFields.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Category details',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      ..._buildMetadataPayload()
                          .entries
                          .take(6)
                          .map((entry) => Text('${entry.key}: ${entry.value}'))
                          .toList(growable: false),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Publishing will submit your listing for marketplace visibility. Draft remains saved until publish succeeds.',
                    ),
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
