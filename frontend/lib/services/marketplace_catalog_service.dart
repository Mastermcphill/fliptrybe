import 'dart:math';

import 'listing_service.dart';
import 'api_client.dart';
import 'api_config.dart';

class MarketplaceRemoteSearchResult {
  const MarketplaceRemoteSearchResult({
    required this.items,
    required this.supportedFilters,
  });

  final List<Map<String, dynamic>> items;
  final Map<String, bool> supportedFilters;
}

class MarketplaceCatalogService {
  MarketplaceCatalogService({ListingService? listingService})
      : _listingService = listingService ?? ListingService();

  final ListingService _listingService;

  final List<Map<String, dynamic>> _fallback = [
    {
      'id': 1001,
      'title': 'iPhone 12 128GB',
      'price': 450000,
      'condition': 'Used - Like New',
      'category': 'Phones',
      'description': 'Clean device, battery health 92%.',
      'state': 'Lagos',
      'city': 'Ikeja',
      'is_demo': true,
      'is_boosted': true,
      'created_at': '2026-01-25T10:00:00Z',
    },
    {
      'id': 1002,
      'title': 'Samsung Galaxy S21',
      'price': 380000,
      'condition': 'Used - Good',
      'category': 'Phones',
      'description': 'Very clean with charger included.',
      'state': 'Lagos',
      'city': 'Lekki',
      'is_demo': true,
      'created_at': '2026-01-27T09:00:00Z',
    },
    {
      'id': 1003,
      'title': 'Leather Sofa Set',
      'price': 250000,
      'condition': 'Used - Good',
      'category': 'Furniture',
      'description': '3-seater + 2 chairs.',
      'state': 'Rivers',
      'city': 'Port Harcourt',
      'is_demo': true,
      'created_at': '2026-01-28T11:00:00Z',
    },
    {
      'id': 1004,
      'title': 'Wooden Dining Table',
      'price': 180000,
      'condition': 'Used - Fair',
      'category': 'Furniture',
      'description': 'Solid wood with 6 chairs.',
      'state': 'Oyo',
      'city': 'Ibadan',
      'is_demo': true,
      'created_at': '2026-01-29T12:00:00Z',
    },
    {
      'id': 1005,
      'title': 'Nike Air Max',
      'price': 65000,
      'condition': 'Used - Like New',
      'category': 'Fashion',
      'description': 'Size 42, worn twice.',
      'state': 'Federal Capital Territory',
      'city': 'Abuja',
      'is_demo': true,
      'created_at': '2026-01-31T10:00:00Z',
    },
    {
      'id': 1006,
      'title': 'LG 55-inch Smart TV',
      'price': 320000,
      'condition': 'Used - Good',
      'category': 'Electronics',
      'description': '4K UHD with HDR support.',
      'state': 'Ogun',
      'city': 'Abeokuta',
      'is_demo': true,
      'created_at': '2026-02-01T13:00:00Z',
    },
    {
      'id': 1007,
      'title': 'PlayStation 5',
      'price': 520000,
      'condition': 'Used - Like New',
      'category': 'Electronics',
      'description': 'Includes one controller and two games.',
      'state': 'Lagos',
      'city': 'Yaba',
      'is_demo': true,
      'created_at': '2026-02-02T14:00:00Z',
    },
    {
      'id': 1008,
      'title': 'Mountain Bike',
      'price': 95000,
      'condition': 'Used - Good',
      'category': 'Sports',
      'description': '26-inch wheels, recently serviced.',
      'state': 'Kaduna',
      'city': 'Kaduna',
      'is_demo': true,
      'created_at': '2026-02-03T15:00:00Z',
    },
    {
      'id': 1009,
      'title': 'Inverter 1.5kVA',
      'price': 140000,
      'condition': 'Used - Good',
      'category': 'Home',
      'description': 'Works with two batteries.',
      'state': 'Anambra',
      'city': 'Awka',
      'is_demo': true,
      'created_at': '2026-02-04T09:15:00Z',
    },
    {
      'id': 1010,
      'title': 'Office Chair Ergonomic',
      'price': 55000,
      'condition': 'Used - Good',
      'category': 'Home',
      'description': 'Hydraulic support intact.',
      'state': 'Kano',
      'city': 'Kano',
      'is_demo': true,
      'created_at': '2026-02-04T16:00:00Z',
    },
  ];
  String? _searchModeCache;
  Map<String, dynamic>? _featuresCache;

  Future<List<Map<String, dynamic>>> listAll() async {
    final rows = await _listingService.listListings();
    final mapped = rows
        .whereType<Map>()
        .map((raw) => _normalize(Map<String, dynamic>.from(raw)))
        .where((m) => (m['id'] ?? 0) is int && (m['id'] as int) > 0)
        .toList();

    if (mapped.isNotEmpty) {
      return mapped;
    }
    return _fallback.map(_normalize).toList();
  }

  Future<String> searchV2Mode() async {
    final features = await publicFeatures();
    final mode = (features['search_v2_mode'] ?? 'off').toString().toLowerCase();
    if (mode == 'off' || mode == 'shadow' || mode == 'on') {
      _searchModeCache = mode;
      return mode;
    }
    if (_searchModeCache != null) return _searchModeCache!;
    _searchModeCache = 'off';
    return _searchModeCache!;
  }

  Future<Map<String, dynamic>> publicFeatures({bool refresh = false}) async {
    if (!refresh && _featuresCache != null) {
      return Map<String, dynamic>.from(_featuresCache!);
    }
    try {
      final data =
          await ApiClient.instance.getJson(ApiConfig.api('/public/features'));
      if (data is Map && data['features'] is Map) {
        _featuresCache = Map<String, dynamic>.from(data['features'] as Map);
        return Map<String, dynamic>.from(_featuresCache!);
      }
    } catch (_) {}
    _featuresCache = <String, dynamic>{};
    return <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> recommendedRemote({
    String city = '',
    String state = '',
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'limit': '${limit < 1 ? 20 : limit > 60 ? 60 : limit}'
    };
    if (city.trim().isNotEmpty) qp['city'] = city.trim();
    if (state.trim().isNotEmpty) qp['state'] = state.trim();
    final uri = Uri(path: '/public/listings/recommended', queryParameters: qp);
    try {
      final data =
          await ApiClient.instance.getJson(ApiConfig.api(uri.toString()));
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .whereType<Map>()
            .map((raw) => _normalize(Map<String, dynamic>.from(raw)))
            .toList(growable: false);
      }
      if (data is List) {
        return data
            .whereType<Map>()
            .map((raw) => _normalize(Map<String, dynamic>.from(raw)))
            .toList(growable: false);
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  Future<List<String>> titleSuggestions(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return const <String>[];
    final uri = Uri(
      path: '/public/listings/title-suggestions',
      queryParameters: <String, String>{
        'q': query.trim(),
        'limit': '${limit < 1 ? 8 : limit > 20 ? 20 : limit}',
      },
    );
    try {
      final data =
          await ApiClient.instance.getJson(ApiConfig.api(uri.toString()));
      if (data is Map && data['items'] is List) {
        return (data['items'] as List)
            .map(
                (item) => (item is Map ? item['term'] : item).toString().trim())
            .where((term) => term.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <String>[];
  }

  Future<Map<String, dynamic>> favoriteListing({
    required int listingId,
    required bool favorite,
  }) async {
    final path = '/listings/$listingId/favorite';
    try {
      final data = favorite
          ? await ApiClient.instance
              .postJson(ApiConfig.api(path), const <String, dynamic>{})
          : await ApiClient.instance.dio
              .delete(ApiConfig.api(path))
              .then((value) => value.data);
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return <String, dynamic>{'ok': false};
  }

  Future<Map<String, dynamic>> recordListingView(int listingId,
      {String sessionKey = ''}) async {
    final path = '/listings/$listingId/view';
    final payload = <String, dynamic>{};
    if (sessionKey.trim().isNotEmpty)
      payload['session_key'] = sessionKey.trim();
    try {
      final data =
          await ApiClient.instance.postJson(ApiConfig.api(path), payload);
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return <String, dynamic>{'ok': false};
  }

  Future<List<Map<String, dynamic>>> searchRemote({
    String query = '',
    String category = '',
    int? categoryId,
    int? parentCategoryId,
    int? brandId,
    int? modelId,
    String state = '',
    double? minPrice,
    double? maxPrice,
    String condition = '',
    bool? deliveryAvailable,
    bool? inspectionRequired,
    String status = '',
    String sort = 'relevance',
    int limit = 40,
    int offset = 0,
    bool admin = false,
  }) async {
    final result = await searchRemoteDetailed(
      query: query,
      category: category,
      categoryId: categoryId,
      parentCategoryId: parentCategoryId,
      brandId: brandId,
      modelId: modelId,
      state: state,
      minPrice: minPrice,
      maxPrice: maxPrice,
      condition: condition,
      deliveryAvailable: deliveryAvailable,
      inspectionRequired: inspectionRequired,
      status: status,
      sort: sort,
      limit: limit,
      offset: offset,
      admin: admin,
    );
    return result.items;
  }

  Future<MarketplaceRemoteSearchResult> searchRemoteDetailed({
    String query = '',
    String category = '',
    int? categoryId,
    int? parentCategoryId,
    int? brandId,
    int? modelId,
    String state = '',
    double? minPrice,
    double? maxPrice,
    String condition = '',
    bool? deliveryAvailable,
    bool? inspectionRequired,
    String status = '',
    String sort = 'relevance',
    int limit = 40,
    int offset = 0,
    bool admin = false,
  }) async {
    final qp = <String, String>{
      'q': query.trim(),
      'sort': _mapSort(sort),
      'limit': '$limit',
      'offset': '$offset',
    };
    if (category.trim().isNotEmpty && category.trim().toLowerCase() != 'all') {
      qp['category'] = category.trim();
    }
    if (categoryId != null && categoryId > 0) {
      qp['category_id'] = '$categoryId';
    }
    if (parentCategoryId != null && parentCategoryId > 0) {
      qp['parent_category_id'] = '$parentCategoryId';
    }
    if (brandId != null && brandId > 0) {
      qp['brand_id'] = '$brandId';
    }
    if (modelId != null && modelId > 0) {
      qp['model_id'] = '$modelId';
    }
    if (state.trim().isNotEmpty &&
        state.trim().toLowerCase() != 'all nigeria') {
      qp['state'] = state.trim();
    }
    if (minPrice != null) qp['min_price'] = minPrice.toStringAsFixed(0);
    if (maxPrice != null) qp['max_price'] = maxPrice.toStringAsFixed(0);
    if (condition.trim().isNotEmpty) qp['condition'] = condition.trim();
    if (status.trim().isNotEmpty && status.trim().toLowerCase() != 'all') {
      qp['status'] = status.trim();
    }
    if (deliveryAvailable != null) {
      qp['delivery_available'] = deliveryAvailable ? '1' : '0';
    }
    if (inspectionRequired != null) {
      qp['inspection_required'] = inspectionRequired ? '1' : '0';
    }
    final path = admin ? '/admin/listings/search' : '/public/listings/search';
    final uri = Uri(path: path, queryParameters: qp);
    final defaultFilters = <String, bool>{
      'delivery_available': false,
      'inspection_required': false,
    };
    try {
      final data =
          await ApiClient.instance.getJson(ApiConfig.api(uri.toString()));
      if (data is Map && data['items'] is List) {
        final items = (data['items'] as List)
            .whereType<Map>()
            .map((raw) => _normalize(Map<String, dynamic>.from(raw)))
            .toList();
        final supported = <String, bool>{...defaultFilters};
        final rawSupported = data['supported_filters'];
        if (rawSupported is Map) {
          for (final entry in rawSupported.entries) {
            supported[entry.key.toString()] = entry.value == true;
          }
        }
        return MarketplaceRemoteSearchResult(
          items: items,
          supportedFilters: supported,
        );
      }
    } catch (_) {}
    return MarketplaceRemoteSearchResult(
      items: const <Map<String, dynamic>>[],
      supportedFilters: defaultFilters,
    );
  }

  String _mapSort(String sort) {
    switch (sort) {
      case 'price_low':
        return 'price_asc';
      case 'price_high':
        return 'price_desc';
      case 'newest':
        return 'newest';
      default:
        return 'relevance';
    }
  }

  List<Map<String, dynamic>> recommended(List<Map<String, dynamic>> source,
      {int limit = 10}) {
    final out = [...source];
    out.sort((a, b) => _score(b).compareTo(_score(a)));
    return out.take(limit).toList();
  }

  List<Map<String, dynamic>> trending(List<Map<String, dynamic>> source,
      {int limit = 10}) {
    final out = [...source];
    out.sort((a, b) {
      final ap = (_asNum(a['price']) / 1000).floor();
      final bp = (_asNum(b['price']) / 1000).floor();
      final aId =
          a['id'] is int ? a['id'] as int : int.tryParse('${a['id']}') ?? 0;
      final bId =
          b['id'] is int ? b['id'] as int : int.tryParse('${b['id']}') ?? 0;
      return ((bp % 17) + bId).compareTo((ap % 17) + aId);
    });
    return out.take(limit).toList();
  }

  List<Map<String, dynamic>> newest(List<Map<String, dynamic>> source,
      {int limit = 10}) {
    final out = [...source];
    out.sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
    return out.take(limit).toList();
  }

  List<Map<String, dynamic>> bestValue(List<Map<String, dynamic>> source,
      {int limit = 10}) {
    final out = [...source];
    out.sort((a, b) => _asNum(a['price']).compareTo(_asNum(b['price'])));
    return out.take(limit).toList();
  }

  List<Map<String, dynamic>> applyFilters(
    List<Map<String, dynamic>> source, {
    String query = '',
    String category = 'All',
    int? categoryId,
    int? parentCategoryId,
    int? brandId,
    int? modelId,
    String state = 'All Nigeria',
    double? minPrice,
    double? maxPrice,
    List<String> conditions = const [],
    String sort = 'relevance',
  }) {
    final q = query.trim().toLowerCase();
    final activeConditions = conditions.map((e) => e.toLowerCase()).toSet();

    var out = source.where((item) {
      final title = (item['title'] ?? '').toString().toLowerCase();
      final description = (item['description'] ?? '').toString().toLowerCase();
      final condition = (item['condition'] ?? '').toString().toLowerCase();
      final itemCategory = (item['category'] ?? '').toString();
      final itemCategoryId = item['category_id'] is int
          ? item['category_id'] as int
          : int.tryParse('${item['category_id'] ?? ''}');
      final itemBrandId = item['brand_id'] is int
          ? item['brand_id'] as int
          : int.tryParse('${item['brand_id'] ?? ''}');
      final itemModelId = item['model_id'] is int
          ? item['model_id'] as int
          : int.tryParse('${item['model_id'] ?? ''}');
      final itemState = (item['state'] ?? '').toString();
      final price = _asNum(item['price']);

      final matchesQuery =
          q.isEmpty || title.contains(q) || description.contains(q);
      final matchesCategory = category == 'All' || category == itemCategory;
      final matchesCategoryId = categoryId == null || itemCategoryId == categoryId;
      final matchesParentCategory = parentCategoryId == null ||
          itemCategoryId == parentCategoryId ||
          itemCategory.toLowerCase().contains(category.toLowerCase());
      final matchesBrand = brandId == null || itemBrandId == brandId;
      final matchesModel = modelId == null || itemModelId == modelId;
      final matchesState = state == 'All Nigeria' || state == itemState;
      final matchesMin = minPrice == null || price >= minPrice;
      final matchesMax = maxPrice == null || price <= maxPrice;
      final matchesCondition = activeConditions.isEmpty ||
          activeConditions.any((needle) => condition.contains(needle));

      return matchesQuery &&
          matchesCategory &&
          matchesCategoryId &&
          matchesParentCategory &&
          matchesBrand &&
          matchesModel &&
          matchesState &&
          matchesMin &&
          matchesMax &&
          matchesCondition;
    }).toList();

    out.sort((a, b) {
      switch (sort) {
        case 'newest':
          return _createdAt(b).compareTo(_createdAt(a));
        case 'price_low':
          return _asNum(a['price']).compareTo(_asNum(b['price']));
        case 'price_high':
          return _asNum(b['price']).compareTo(_asNum(a['price']));
        case 'distance':
          return ((a['state'] ?? '').toString())
              .compareTo((b['state'] ?? '').toString());
        case 'relevance':
        default:
          return _score(b, query: q).compareTo(_score(a, query: q));
      }
    });

    return out;
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> raw) {
    final id = raw['id'] is int
        ? raw['id'] as int
        : int.tryParse(raw['id']?.toString() ?? '') ??
            Random().nextInt(900000) + 1;

    return {
      ...raw,
      'id': id,
      'title': (raw['title'] ?? 'Untitled listing').toString(),
      'description': (raw['description'] ?? '').toString(),
      'price': _asNum(raw['price']),
      'condition': (raw['condition'] ?? 'Used').toString(),
      'category': (raw['category'] ?? 'All').toString(),
      'category_id': int.tryParse('${raw['category_id'] ?? ''}'),
      'brand_id': int.tryParse('${raw['brand_id'] ?? ''}'),
      'model_id': int.tryParse('${raw['model_id'] ?? ''}'),
      'state': (raw['state'] ?? '').toString(),
      'city': (raw['city'] ?? '').toString(),
      'locality': (raw['locality'] ?? '').toString(),
      'image': (raw['image'] ?? raw['image_path'] ?? '').toString(),
      'image_path': (raw['image_path'] ?? raw['image'] ?? '').toString(),
      'is_demo': raw['is_demo'] == true,
      'is_boosted': raw['is_boosted'] == true,
      'views_count': int.tryParse('${raw['views_count'] ?? 0}') ?? 0,
      'favorites_count': int.tryParse('${raw['favorites_count'] ?? 0}') ?? 0,
      'heat_level': (raw['heat_level'] ?? '').toString(),
      'heat_score': int.tryParse('${raw['heat_score'] ?? 0}') ?? 0,
      'ranking_score': int.tryParse('${raw['ranking_score'] ?? 0}') ?? 0,
      'ranking_reason': raw['ranking_reason'] is List
          ? List<String>.from(raw['ranking_reason'] as List)
          : const <String>[],
      'created_at':
          (raw['created_at'] ?? DateTime.now().toIso8601String()).toString(),
    };
  }

  DateTime _createdAt(Map<String, dynamic> item) {
    try {
      return DateTime.parse((item['created_at'] ?? '').toString());
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  double _score(Map<String, dynamic> item, {String query = ''}) {
    final boosted = item['is_boosted'] == true ? 8.0 : 0.0;
    final agePenalty =
        _createdAt(item).difference(DateTime.now()).inHours.abs() / 24.0;
    final priceBand = _asNum(item['price']) <= 100000 ? 2.0 : 0.8;
    final queryHit = query.isEmpty
        ? 0.0
        : ((item['title'] ?? '').toString().toLowerCase().contains(query)
            ? 6.0
            : 0.0);
    return boosted + priceBand + queryHit - agePenalty;
  }

  double _asNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
