import 'package:flutter/material.dart';

import '../services/feed_service.dart';

class SearchDemoScreen extends StatefulWidget {
  final String initialQuery;
  const SearchDemoScreen({super.key, this.initialQuery = ''});

  @override
  State<SearchDemoScreen> createState() => _SearchDemoScreenState();
}

class _SearchDemoScreenState extends State<SearchDemoScreen> {
  final _feed = FeedService();
  final _q = TextEditingController();

  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _q.text = widget.initialQuery;
    _items = _feed.getFeed();
  }

  void _reload() {
    setState(() => _items = _feed.getFeed());
  }

  bool _match(Map<String, dynamic> m, String query) {
    final q = query.toLowerCase();
    final title = (m['title'] ?? '').toString().toLowerCase();
    final desc = (m['description'] ?? '').toString().toLowerCase();
    return title.contains(q) || desc.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                labelText: 'Search listings',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() {}),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = (snap.data ?? const [])
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();

                final q = _q.text.trim();
                final filtered = q.isEmpty
                    ? items
                    : items.where((m) => _match(m, q)).toList();

                if (filtered.isEmpty) {
                  return const Center(
                      child: Text(
                          'No matches yet. Create listings and search again.'));
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final m = filtered[i];
                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: ListTile(
                        title: Text((m['title'] ?? '').toString(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text((m['description'] ?? '').toString(),
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
