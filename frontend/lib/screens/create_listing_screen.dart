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
import '../utils/formatters.dart';
import '../widgets/email_verification_dialog.dart';

class CreateListingScreen extends StatefulWidget {
  const CreateListingScreen({super.key});

  @override
  State<CreateListingScreen> createState() => _CreateListingScreenState();
}

class _CreateListingScreenState extends State<CreateListingScreen> {
  static const _draftKey = 'create_listing_draft_v2';

  final _listingService = ListingService();
  final _feedService = FeedService();
  final _catalog = MarketplaceCatalogService();
  final _categorySvc = CategoryService();

  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _localityCtrl = TextEditingController();
  final _lgaCtrl = TextEditingController();

  int _step = 0;
  bool _loading = false;
  bool _loadingLocations = false;
  bool _showValidation = false;
  bool _inspectionEnabled = true;
  bool _deliveryEnabled = true;
  bool _loadingSuggestions = false;

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

  Future<void> _loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final draft = Map<String, dynamic>.from(decoded);
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
      if (_selectedImagePath != null &&
          _selectedImagePath!.trim().isNotEmpty &&
          File(_selectedImagePath!).existsSync()) {
        _selectedImage = File(_selectedImagePath!);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Ignore invalid draft payload and continue.
    }
  }

  Future<void> _saveDraft() async {
    final prefs = await SharedPreferences.getInstance();
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
      'image_path': _selectedImagePath ?? _selectedImage?.path ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    };
    await prefs.setString(_draftKey, jsonEncode(payload));
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
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
    if (!mounted) return;
    final flat = _flattenCategories(tree);
    setState(() => _taxonomy = flat);
    await _loadBrandModelOptions();
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
            (double.tryParse(_priceCtrl.text.trim()) ?? 0) > 0;
      case 2:
        return _selectedImage != null;
      case 3:
        return true;
      case 4:
        return _titleCtrl.text.trim().isNotEmpty &&
            (double.tryParse(_priceCtrl.text.trim()) ?? 0) > 0 &&
            _selectedImage != null;
      default:
        return false;
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    if (!_validateCurrentStep()) return;

    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;

    if (title.isEmpty || price <= 0 || _selectedImage == null) {
      _showSnack('Complete all required fields before publishing.');
      return;
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
      category: _category,
      categoryId: _categoryId,
      brandId: _brandId,
      modelId: _modelId,
      state: _state,
      city: _cityCtrl.text.trim(),
      locality: _localityCtrl.text.trim(),
      imagePath: _selectedImage!.path,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    final ok = res['ok'] == true;
    final code = (res['code'] ?? '').toString().trim().toUpperCase();
    final msg = (res['message'] ?? res['error'] ?? 'Failed to publish listing')
        .toString();

    if (!ok && ApiService.isEmailNotVerified(res)) {
      await showEmailVerificationRequiredDialog(
        context,
        message: msg,
        onRetry: _submitListing,
      );
      return;
    }

    if (ok) {
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
                    });
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
                  child: ElevatedButton(
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
                    child: Text(
                      _loading
                          ? 'Please wait...'
                          : (isLast ? 'Publish listing' : 'Continue'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
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
                    child: Text(_step == 0 ? 'Cancel' : 'Back'),
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
                      setState(() {
                        _parentCategoryId = value;
                        _categoryId = null;
                        _brandId = null;
                        _modelId = null;
                      });
                      await _loadBrandModelOptions();
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
                      await _loadBrandModelOptions();
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
                    value: _category,
                    items: const [
                      'General',
                      'Electronics',
                      'Phones',
                      'Furniture',
                      'Fashion',
                      'Home',
                      'Sports',
                    ]
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      setState(() => _category = value);
                      await _saveDraft();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _state,
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _condition,
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
                    Text(
                        'Location: ${_cityCtrl.text.trim()}, ${displayState(_state)}'),
                    Text(
                        'Delivery: ${_deliveryEnabled ? 'Enabled' : 'Disabled'}'),
                    Text(
                        'Inspection: ${_inspectionEnabled ? 'Enabled' : 'Disabled'}'),
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
