import 'package:flutter/material.dart';

import '../../constants/ng_states.dart';
import '../../models/marketplace_query_state.dart';
import '../../services/saved_search_service.dart';
import '../../ui/components/ft_components.dart';
import 'marketplace_search_results_screen.dart';

class SavedSearchesScreen extends StatefulWidget {
  const SavedSearchesScreen({super.key});

  @override
  State<SavedSearchesScreen> createState() => _SavedSearchesScreenState();
}

class _SavedSearchesScreenState extends State<SavedSearchesScreen> {
  final _svc = SavedSearchService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      final rows = await _svc.list();
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

  Future<void> _delete(int id) async {
    final res = await _svc.remove(id);
    if (!mounted) return;
    if (res['ok'] == true) {
      await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text((res['message'] ?? 'Unable to delete').toString())),
    );
  }

  Future<void> _rename(Map<String, dynamic> item) async {
    final id = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id'] ?? ''}') ?? 0;
    if (id <= 0) return;
    final ctrl = TextEditingController(text: (item['name'] ?? '').toString());
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename saved search'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Search name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || name.trim().isEmpty) return;
    final res = await _svc.update(id: id, name: name.trim());
    if (!mounted) return;
    if (res['ok'] == true) {
      await _load();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text((res['message'] ?? 'Unable to rename').toString())),
    );
  }

  Future<void> _openSearch(Map<String, dynamic> item) async {
    final id = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id'] ?? ''}') ?? 0;
    final queryRaw = item['query_json'];
    final queryMap = queryRaw is Map
        ? Map<String, dynamic>.from(queryRaw)
        : <String, dynamic>{};
    final state = MarketplaceQueryState.fromMap(queryMap);
    if (id > 0) {
      await _svc.use(id);
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketplaceSearchResultsScreen(
          initialQueryState: state.copyWith(
            state: state.state.isEmpty ? allNigeriaLabel : state.state,
          ),
        ),
      ),
    );
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
                        final id = item['id'] is int
                            ? item['id'] as int
                            : int.tryParse('${item['id'] ?? ''}') ?? 0;
                        final name = (item['name'] ?? 'Saved search').toString();
                        final vertical =
                            (item['vertical'] ?? 'marketplace').toString();
                        final updatedAt = (item['updated_at'] ?? '').toString();
                        return FTCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text('Vertical: $vertical'),
                              if (updatedAt.trim().isNotEmpty)
                                Text('Updated: $updatedAt'),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  FTSecondaryButton(
                                    label: 'Apply',
                                    icon: Icons.play_arrow_outlined,
                                    onPressed: id > 0
                                        ? () => _openSearch(item)
                                        : null,
                                  ),
                                  const SizedBox(width: 8),
                                  FTSecondaryButton(
                                    label: 'Rename',
                                    icon: Icons.edit_outlined,
                                    onPressed:
                                        id > 0 ? () => _rename(item) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  FTSecondaryButton(
                                    label: 'Delete',
                                    icon: Icons.delete_outline,
                                    onPressed:
                                        id > 0 ? () => _delete(id) : null,
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
