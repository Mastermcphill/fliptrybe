class MarketplaceQueryState {
  const MarketplaceQueryState({
    this.query = '',
    this.category = 'All',
    this.categoryId,
    this.parentCategoryId,
    this.brandId,
    this.modelId,
    this.state = 'All Nigeria',
    this.sort = 'relevance',
    this.minPrice,
    this.maxPrice,
    this.conditions = const <String>[],
    this.deliveryAvailable = false,
    this.inspectionRequired = false,
    this.gridView = true,
  });

  final String query;
  final String category;
  final int? categoryId;
  final int? parentCategoryId;
  final int? brandId;
  final int? modelId;
  final String state;
  final String sort;
  final double? minPrice;
  final double? maxPrice;
  final List<String> conditions;
  final bool deliveryAvailable;
  final bool inspectionRequired;
  final bool gridView;

  MarketplaceQueryState copyWith({
    String? query,
    String? category,
    int? categoryId,
    int? parentCategoryId,
    int? brandId,
    int? modelId,
    bool clearCategoryId = false,
    bool clearParentCategoryId = false,
    bool clearBrandId = false,
    bool clearModelId = false,
    String? state,
    String? sort,
    double? minPrice,
    double? maxPrice,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    List<String>? conditions,
    bool? deliveryAvailable,
    bool? inspectionRequired,
    bool? gridView,
  }) {
    return MarketplaceQueryState(
      query: query ?? this.query,
      category: category ?? this.category,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      parentCategoryId: clearParentCategoryId
          ? null
          : (parentCategoryId ?? this.parentCategoryId),
      brandId: clearBrandId ? null : (brandId ?? this.brandId),
      modelId: clearModelId ? null : (modelId ?? this.modelId),
      state: state ?? this.state,
      sort: sort ?? this.sort,
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      conditions: conditions ?? this.conditions,
      deliveryAvailable: deliveryAvailable ?? this.deliveryAvailable,
      inspectionRequired: inspectionRequired ?? this.inspectionRequired,
      gridView: gridView ?? this.gridView,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'query': query,
      'category': category,
      'categoryId': categoryId,
      'parentCategoryId': parentCategoryId,
      'brandId': brandId,
      'modelId': modelId,
      'state': state,
      'sort': sort,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'conditions': conditions,
      'deliveryAvailable': deliveryAvailable,
      'inspectionRequired': inspectionRequired,
      'gridView': gridView,
    };
  }

  static MarketplaceQueryState fromMap(Map<String, dynamic> map) {
    return MarketplaceQueryState(
      query: (map['query'] ?? '').toString(),
      category: (map['category'] ?? 'All').toString(),
      categoryId: map['categoryId'] is num
          ? (map['categoryId'] as num).toInt()
          : int.tryParse((map['categoryId'] ?? '').toString()),
      parentCategoryId: map['parentCategoryId'] is num
          ? (map['parentCategoryId'] as num).toInt()
          : int.tryParse((map['parentCategoryId'] ?? '').toString()),
      brandId: map['brandId'] is num
          ? (map['brandId'] as num).toInt()
          : int.tryParse((map['brandId'] ?? '').toString()),
      modelId: map['modelId'] is num
          ? (map['modelId'] as num).toInt()
          : int.tryParse((map['modelId'] ?? '').toString()),
      state: (map['state'] ?? 'All Nigeria').toString(),
      sort: (map['sort'] ?? 'relevance').toString(),
      minPrice: map['minPrice'] is num
          ? (map['minPrice'] as num).toDouble()
          : double.tryParse((map['minPrice'] ?? '').toString()),
      maxPrice: map['maxPrice'] is num
          ? (map['maxPrice'] as num).toDouble()
          : double.tryParse((map['maxPrice'] ?? '').toString()),
      conditions: (map['conditions'] is List)
          ? (map['conditions'] as List)
              .map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList(growable: false)
          : const <String>[],
      deliveryAvailable: map['deliveryAvailable'] == true,
      inspectionRequired: map['inspectionRequired'] == true,
      gridView: map['gridView'] != false,
    );
  }
}
