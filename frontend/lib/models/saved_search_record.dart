import 'marketplace_query_state.dart';

class SavedSearchRecord {
  SavedSearchRecord({
    required this.key,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });

  final String key;
  final MarketplaceQueryState state;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'key': key,
      ...state.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static SavedSearchRecord fromMap(Map<String, dynamic> raw) {
    final now = DateTime.now().toUtc();
    DateTime parseDate(dynamic value) {
      if (value == null) return now;
      try {
        return DateTime.parse(value.toString()).toUtc();
      } catch (_) {
        return now;
      }
    }

    final key = (raw['key'] ?? '').toString().trim();
    return SavedSearchRecord(
      key: key,
      state: MarketplaceQueryState.fromMap(raw),
      createdAt: parseDate(raw['createdAt']),
      updatedAt: parseDate(raw['updatedAt']),
    );
  }
}
