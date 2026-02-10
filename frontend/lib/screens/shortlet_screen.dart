import 'package:flutter/material.dart';
import '../constants/ng_states.dart';
import '../services/shortlet_service.dart';
import 'marketplace_filters_screen.dart';
import 'shortlet_detail_screen.dart';

class ShortletScreen extends StatefulWidget {
  const ShortletScreen({super.key});

  @override
  State<ShortletScreen> createState() => _ShortletScreenState();
}

class _ShortletScreenState extends State<ShortletScreen> {
  final _svc = ShortletService();
  final _searchCtrl = TextEditingController();
  String _selectedState = allNigeriaLabel;

  Future<List<dynamic>> _load() {
    final state = _selectedState == allNigeriaLabel ? '' : _selectedState;
    return _svc.listShortlets(state: state);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatNaira(dynamic v) {
    final amount = double.tryParse((v ?? '').toString()) ?? 0;
    final raw = amount.round().toString();
    final out = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final idxFromEnd = raw.length - i;
      out.write(raw[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) {
        out.write(',');
      }
    }
    return 'NGN ${out.toString()}';
  }

  String _formatLocation(String city, String state) {
    final c = city.trim();
    final s = state.trim();
    if (c.isEmpty && s.isEmpty) return 'Location not set';
    if (c.isEmpty) return s;
    if (s.isEmpty) return c;
    return '$c, $s';
  }

  Future<void> _openFilters() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MarketplaceFiltersScreen(
          categories: const ['All', 'Shortlet'],
          selectedCategory: 'Shortlet',
          initialQuery: _searchCtrl.text,
          initialState: _selectedState,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      _searchCtrl.text = (result['query'] ?? '').toString();
      final state = (result['state'] ?? allNigeriaLabel).toString();
      _selectedState = state.isEmpty ? allNigeriaLabel : state;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Haven Short-lets')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search by city or name',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _openFilters,
                  tooltip: 'Filters',
                  icon: const Icon(Icons.tune),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _selectedState,
              items: <String>[allNigeriaLabel, ...nigeriaStates]
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(displayState(s))))
                  .toList(),
              decoration: const InputDecoration(
                labelText: 'State',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedState = value);
              },
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _load(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return const Center(
                        child: Text('Could not load apartments.'));
                  }

                  final raw = snapshot.data ?? [];
                  final q = _searchCtrl.text.trim().toLowerCase();
                  final items = raw.where((m) {
                    if (m is! Map) return false;
                    final title = (m['title'] ?? '').toString().toLowerCase();
                    final city = (m['city'] ?? '').toString().toLowerCase();
                    final state = (m['state'] ?? '').toString().toLowerCase();
                    if (q.isEmpty) return true;
                    return title.contains(q) ||
                        city.contains(q) ||
                        state.contains(q);
                  }).toList();

                  if (items.isEmpty) {
                    return const Center(child: Text('No apartments found'));
                  }

                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final m = items[i] as Map;
                      final title = (m['title'] ?? '').toString();
                      final city = (m['city'] ?? '').toString();
                      final state = (m['state'] ?? '').toString();
                      final beds = (m['rooms'] ?? m['beds'] ?? '').toString();
                      final baths =
                          (m['bathrooms'] ?? m['baths'] ?? '').toString();

                      final priceText =
                          _formatNaira(m['nightly_price'] ?? m['price']);
                      final locText = _formatLocation(city, state);
                      final bedsText = beds.trim().isEmpty ? '-' : beds;
                      final bathsText = baths.trim().isEmpty ? '-' : baths;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ShortletDetailScreen(
                                    shortlet: Map<String, dynamic>.from(m)),
                              ),
                            );
                          },
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.apartment_outlined,
                                        size: 36, color: Color(0xFF60A5FA)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        Text(locText,
                                            style: TextStyle(
                                                color: Colors.grey.shade600)),
                                        const SizedBox(height: 6),
                                        Text(
                                            'Beds: $bedsText | Baths: $bathsText',
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(priceText,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 2),
                                      const Text('/ night',
                                          style: TextStyle(fontSize: 12)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
