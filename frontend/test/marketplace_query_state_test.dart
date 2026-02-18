import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/models/marketplace_query_state.dart';
import 'package:fliptrybe/models/saved_search_record.dart';

void main() {
  test('MarketplaceQueryState serializes and restores full filter state', () {
    const state = MarketplaceQueryState(
      query: 'iphone',
      category: 'Phones',
      listingType: 'vehicle',
      vehicleMake: 'Toyota',
      vehicleModel: 'Corolla',
      vehicleYear: 2018,
      batteryType: 'Lithium',
      inverterCapacity: '5kVA',
      lithiumOnly: true,
      propertyType: 'Rent',
      bedroomsMin: 2,
      bedroomsMax: 4,
      bathroomsMin: 2,
      bathroomsMax: 3,
      furnishedOnly: true,
      servicedOnly: true,
      landSizeMin: 120,
      landSizeMax: 560,
      titleDocumentType: 'C of O',
      city: 'Lekki',
      area: 'Phase 1',
      state: 'Lagos',
      sort: 'price_low',
      minPrice: 50000,
      maxPrice: 300000,
      conditions: ['like new', 'good'],
      gridView: false,
    );

    final restored = MarketplaceQueryState.fromMap(state.toMap());
    expect(restored.query, 'iphone');
    expect(restored.category, 'Phones');
    expect(restored.listingType, 'vehicle');
    expect(restored.vehicleMake, 'Toyota');
    expect(restored.vehicleModel, 'Corolla');
    expect(restored.vehicleYear, 2018);
    expect(restored.batteryType, 'Lithium');
    expect(restored.inverterCapacity, '5kVA');
    expect(restored.lithiumOnly, isTrue);
    expect(restored.propertyType, 'Rent');
    expect(restored.bedroomsMin, 2);
    expect(restored.bedroomsMax, 4);
    expect(restored.bathroomsMin, 2);
    expect(restored.bathroomsMax, 3);
    expect(restored.furnishedOnly, isTrue);
    expect(restored.servicedOnly, isTrue);
    expect(restored.landSizeMin, 120);
    expect(restored.landSizeMax, 560);
    expect(restored.titleDocumentType, 'C of O');
    expect(restored.city, 'Lekki');
    expect(restored.area, 'Phase 1');
    expect(restored.state, 'Lagos');
    expect(restored.sort, 'price_low');
    expect(restored.minPrice, 50000);
    expect(restored.maxPrice, 300000);
    expect(restored.conditions, ['like new', 'good']);
    expect(restored.gridView, isFalse);
  });

  test('SavedSearchRecord keeps key and timestamps', () {
    final created = DateTime.utc(2026, 2, 12, 10, 0, 0);
    final updated = DateTime.utc(2026, 2, 12, 11, 0, 0);
    final record = SavedSearchRecord(
      key: 'k1',
      state: const MarketplaceQueryState(query: 'bike'),
      createdAt: created,
      updatedAt: updated,
    );

    final restored = SavedSearchRecord.fromMap(record.toMap());
    expect(restored.key, 'k1');
    expect(restored.state.query, 'bike');
    expect(restored.createdAt.toUtc(), created);
    expect(restored.updatedAt.toUtc(), updated);
  });
}
