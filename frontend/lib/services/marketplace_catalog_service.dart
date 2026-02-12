import 'dart:math';

import 'listing_service.dart';

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
      final aId = a['id'] is int ? a['id'] as int : int.tryParse('${a['id']}') ?? 0;
      final bId = b['id'] is int ? b['id'] as int : int.tryParse('${b['id']}') ?? 0;
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
      final itemState = (item['state'] ?? '').toString();
      final price = _asNum(item['price']);

      final matchesQuery = q.isEmpty || title.contains(q) || description.contains(q);
      final matchesCategory = category == 'All' || category == itemCategory;
      final matchesState = state == 'All Nigeria' || state == itemState;
      final matchesMin = minPrice == null || price >= minPrice;
      final matchesMax = maxPrice == null || price <= maxPrice;
      final matchesCondition = activeConditions.isEmpty ||
          activeConditions.any((needle) => condition.contains(needle));

      return matchesQuery &&
          matchesCategory &&
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
        : int.tryParse(raw['id']?.toString() ?? '') ?? Random().nextInt(900000) + 1;

    return {
      ...raw,
      'id': id,
      'title': (raw['title'] ?? 'Untitled listing').toString(),
      'description': (raw['description'] ?? '').toString(),
      'price': _asNum(raw['price']),
      'condition': (raw['condition'] ?? 'Used').toString(),
      'category': (raw['category'] ?? 'All').toString(),
      'state': (raw['state'] ?? '').toString(),
      'city': (raw['city'] ?? '').toString(),
      'locality': (raw['locality'] ?? '').toString(),
      'image': (raw['image'] ?? raw['image_path'] ?? '').toString(),
      'image_path': (raw['image_path'] ?? raw['image'] ?? '').toString(),
      'is_demo': raw['is_demo'] == true,
      'is_boosted': raw['is_boosted'] == true,
      'created_at': (raw['created_at'] ?? DateTime.now().toIso8601String()).toString(),
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
    final agePenalty = _createdAt(item).difference(DateTime.now()).inHours.abs() / 24.0;
    final priceBand = _asNum(item['price']) <= 100000 ? 2.0 : 0.8;
    final queryHit = query.isEmpty
        ? 0.0
        : ((item['title'] ?? '').toString().toLowerCase().contains(query) ? 6.0 : 0.0);
    return boosted + priceBand + queryHit - agePenalty;
  }

  double _asNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
