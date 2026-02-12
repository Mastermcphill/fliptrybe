import 'package:flutter/material.dart';

import '../../services/marketplace_prefs_service.dart';
import '../../ui/components/ft_components.dart';
import 'marketplace_search_results_screen.dart';

class SavedSearchesScreen extends StatefulWidget {
  const SavedSearchesScreen({super.key});

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  final _prefs = MarketplacePrefsService();
  bool _loading = true;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _prefs.loadSavedSearches();
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _delete(String key) async {
    await _prefs.deleteSearch(key);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Saved Searches',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const FTEmptyState(
                  icon: Icons.bookmarks_outlined,
                  title: 'No saved searches',
                  subtitle: 'Save filters from the search results screen to reuse them quickly.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final item = _items[index];
                    final key = (item['key'] ?? '').toString();
                    final query = (item['query'] ?? '').toString();
                    final category = (item['category'] ?? 'All').toString();
                    final state = (item['state'] ?? 'All Nigeria').toString();
                    final sort = (item['sort'] ?? 'relevance').toString();
                    return FTCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            query.isEmpty ? 'Saved search' : query,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          Text('Category: $category'),
                          Text('State: $state'),
                          Text('Sort: $sort'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FTSecondaryButton(
                                label: 'Open',
                                icon: Icons.open_in_new,
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MarketplaceSearchResultsScreen(
                                        initialQuery: query,
                                        initialCategory: category,
                                        initialState: state,
                                        initialSort: sort,
                                        initialMinPrice: item['minPrice'] is num
                                            ? (item['minPrice'] as num).toDouble()
                                            : null,
                                        initialMaxPrice: item['maxPrice'] is num
                                            ? (item['maxPrice'] as num).toDouble()
                                            : null,
                                        initialConditions:
                                            ((item['conditions'] as List?) ?? const <dynamic>[])
                                                .map((e) => e.toString())
                                                .toList(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              FTSecondaryButton(
                                label: 'Delete',
                                icon: Icons.delete_outline,
                                onPressed: key.trim().isEmpty ? null : () => _delete(key),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
