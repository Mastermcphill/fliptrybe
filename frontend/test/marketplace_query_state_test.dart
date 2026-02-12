import 'package:flutter_test/flutter_test.dart';
import 'package:fliptrybe/models/marketplace_query_state.dart';
import 'package:fliptrybe/models/saved_search_record.dart';

void main() {
  test('MarketplaceQueryState serializes and restores full filter state', () {
    const state = MarketplaceQueryState(
      query: 'iphone',
      category: 'Phones',
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
