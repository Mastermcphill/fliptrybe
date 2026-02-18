class MarketplaceQueryState {
  const MarketplaceQueryState({
    this.query = '',
    this.category = 'All',
    this.categoryId,
    this.parentCategoryId,
    this.brandId,
    this.modelId,
    this.listingType = '',
    this.vehicleMake = '',
    this.vehicleModel = '',
    this.vehicleYear,
    this.batteryType = '',
    this.inverterCapacity = '',
    this.lithiumOnly = false,
    this.propertyType = '',
    this.bedroomsMin,
    this.bedroomsMax,
    this.bathroomsMin,
    this.bathroomsMax,
    this.furnishedOnly = false,
    this.servicedOnly = false,
    this.landSizeMin,
    this.landSizeMax,
    this.titleDocumentType = '',
    this.city = '',
    this.area = '',
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
  final String listingType;
  final String vehicleMake;
  final String vehicleModel;
  final int? vehicleYear;
  final String batteryType;
  final String inverterCapacity;
  final bool lithiumOnly;
  final String propertyType;
  final int? bedroomsMin;
  final int? bedroomsMax;
  final int? bathroomsMin;
  final int? bathroomsMax;
  final bool furnishedOnly;
  final bool servicedOnly;
  final double? landSizeMin;
  final double? landSizeMax;
  final String titleDocumentType;
  final String city;
  final String area;
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
    String? listingType,
    String? vehicleMake,
    String? vehicleModel,
    int? vehicleYear,
    bool clearVehicleYear = false,
    String? batteryType,
    String? inverterCapacity,
    bool? lithiumOnly,
    String? propertyType,
    int? bedroomsMin,
    int? bedroomsMax,
    int? bathroomsMin,
    int? bathroomsMax,
    bool clearBedroomsMin = false,
    bool clearBedroomsMax = false,
    bool clearBathroomsMin = false,
    bool clearBathroomsMax = false,
    bool? furnishedOnly,
    bool? servicedOnly,
    double? landSizeMin,
    double? landSizeMax,
    bool clearLandSizeMin = false,
    bool clearLandSizeMax = false,
    String? titleDocumentType,
    String? city,
    String? area,
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
      listingType: listingType ?? this.listingType,
      vehicleMake: vehicleMake ?? this.vehicleMake,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      vehicleYear: clearVehicleYear ? null : (vehicleYear ?? this.vehicleYear),
      batteryType: batteryType ?? this.batteryType,
      inverterCapacity: inverterCapacity ?? this.inverterCapacity,
      lithiumOnly: lithiumOnly ?? this.lithiumOnly,
      propertyType: propertyType ?? this.propertyType,
      bedroomsMin: clearBedroomsMin ? null : (bedroomsMin ?? this.bedroomsMin),
      bedroomsMax: clearBedroomsMax ? null : (bedroomsMax ?? this.bedroomsMax),
      bathroomsMin:
          clearBathroomsMin ? null : (bathroomsMin ?? this.bathroomsMin),
      bathroomsMax:
          clearBathroomsMax ? null : (bathroomsMax ?? this.bathroomsMax),
      furnishedOnly: furnishedOnly ?? this.furnishedOnly,
      servicedOnly: servicedOnly ?? this.servicedOnly,
      landSizeMin: clearLandSizeMin ? null : (landSizeMin ?? this.landSizeMin),
      landSizeMax: clearLandSizeMax ? null : (landSizeMax ?? this.landSizeMax),
      titleDocumentType: titleDocumentType ?? this.titleDocumentType,
      city: city ?? this.city,
      area: area ?? this.area,
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
      'listingType': listingType,
      'vehicleMake': vehicleMake,
      'vehicleModel': vehicleModel,
      'vehicleYear': vehicleYear,
      'batteryType': batteryType,
      'inverterCapacity': inverterCapacity,
      'lithiumOnly': lithiumOnly,
      'propertyType': propertyType,
      'bedroomsMin': bedroomsMin,
      'bedroomsMax': bedroomsMax,
      'bathroomsMin': bathroomsMin,
      'bathroomsMax': bathroomsMax,
      'furnishedOnly': furnishedOnly,
      'servicedOnly': servicedOnly,
      'landSizeMin': landSizeMin,
      'landSizeMax': landSizeMax,
      'titleDocumentType': titleDocumentType,
      'city': city,
      'area': area,
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
      listingType: (map['listingType'] ?? '').toString(),
      vehicleMake: (map['vehicleMake'] ?? '').toString(),
      vehicleModel: (map['vehicleModel'] ?? '').toString(),
      vehicleYear: map['vehicleYear'] is num
          ? (map['vehicleYear'] as num).toInt()
          : int.tryParse((map['vehicleYear'] ?? '').toString()),
      batteryType: (map['batteryType'] ?? '').toString(),
      inverterCapacity: (map['inverterCapacity'] ?? '').toString(),
      lithiumOnly: map['lithiumOnly'] == true,
      propertyType: (map['propertyType'] ?? '').toString(),
      bedroomsMin: map['bedroomsMin'] is num
          ? (map['bedroomsMin'] as num).toInt()
          : int.tryParse((map['bedroomsMin'] ?? '').toString()),
      bedroomsMax: map['bedroomsMax'] is num
          ? (map['bedroomsMax'] as num).toInt()
          : int.tryParse((map['bedroomsMax'] ?? '').toString()),
      bathroomsMin: map['bathroomsMin'] is num
          ? (map['bathroomsMin'] as num).toInt()
          : int.tryParse((map['bathroomsMin'] ?? '').toString()),
      bathroomsMax: map['bathroomsMax'] is num
          ? (map['bathroomsMax'] as num).toInt()
          : int.tryParse((map['bathroomsMax'] ?? '').toString()),
      furnishedOnly: map['furnishedOnly'] == true,
      servicedOnly: map['servicedOnly'] == true,
      landSizeMin: map['landSizeMin'] is num
          ? (map['landSizeMin'] as num).toDouble()
          : double.tryParse((map['landSizeMin'] ?? '').toString()),
      landSizeMax: map['landSizeMax'] is num
          ? (map['landSizeMax'] as num).toDouble()
          : double.tryParse((map['landSizeMax'] ?? '').toString()),
      titleDocumentType: (map['titleDocumentType'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      area: (map['area'] ?? '').toString(),
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
