import 'package:flutter/material.dart';

import '../../constants/ng_states.dart';
import '../../models/saved_search_record.dart';
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
  String? _error;
  List<SavedSearchRecord> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _prefs.loadSavedSearchRecords();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load saved searches: $e';
      });
    }
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
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                FTSkeleton(height: 118),
                SizedBox(height: 10),
                FTSkeleton(height: 118),
                SizedBox(height: 10),
                FTSkeleton(height: 118),
              ],
            )
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? const FTEmptyState(
                      icon: Icons.bookmarks_outlined,
                      title: 'No saved searches',
                      subtitle:
                          'Save filters from the search results screen to reuse them quickly.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        final key = item.key;
                        final query = item.state.query;
                        final category = item.state.category;
                        final state = item.state.state;
                        final sort = item.state.sort;
                        final updatedAt = item.updatedAt.toLocal().toString();
                        return FTCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                query.isEmpty ? 'Saved search' : query,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text('Category: $category'),
                              Text('State: ${displayState(state)}'),
                              Text('Sort: $sort'),
                              Text('Updated: $updatedAt'),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FTSecondaryButton(
                                    label: 'Open',
                                    icon: Icons.open_in_new,
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MarketplaceSearchResultsScreen(
                                            initialQuery: query,
                                            initialCategory: category,
                                            initialState: state,
                                            initialSort: sort,
                                            initialMinPrice:
                                                item.state.minPrice,
                                            initialMaxPrice:
                                                item.state.maxPrice,
                                            initialConditions:
                                                item.state.conditions,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  FTSecondaryButton(
                                    label: 'Delete',
                                    icon: Icons.delete_outline,
                                    onPressed: key.trim().isEmpty
                                        ? null
                                        : () => _delete(key),
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
