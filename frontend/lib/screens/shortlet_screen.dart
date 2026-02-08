import 'package:flutter/material.dart';
import '../services/shortlet_service.dart';
import 'shortlet_detail_screen.dart';

class ShortletScreen extends StatefulWidget {
  const ShortletScreen({super.key});

  @override
  State<ShortletScreen> createState() => _ShortletScreenState();
}

class _ShortletScreenState extends State<ShortletScreen> {
  final _svc = ShortletService();
  final _searchCtrl = TextEditingController();

  Future<List<dynamic>> _load() {
    return _svc.listShortlets(state: 'Lagos');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.tune),
                )
              ],
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
                    return const Center(child: Text('Could not load apartments.'));
                  }

                  final raw = snapshot.data ?? [];
                  final q = _searchCtrl.text.trim().toLowerCase();
                  final items = raw.where((m) {
                    if (m is! Map) return false;
                    final title = (m['title'] ?? '').toString().toLowerCase();
                    final city = (m['city'] ?? '').toString().toLowerCase();
                    final state = (m['state'] ?? '').toString().toLowerCase();
                    if (q.isEmpty) return true;
                    return title.contains(q) || city.contains(q) || state.contains(q);
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
                      final price = (m['nightly_price'] ?? m['price'] ?? 0).toString();
                      final city = (m['city'] ?? '').toString();
                      final state = (m['state'] ?? '').toString();
                      final id = m['id'];
                      final beds = (m['rooms'] ?? m['beds'] ?? '').toString();
                      final baths = (m['bathrooms'] ?? m['baths'] ?? '').toString();

                      String _fmtNaira(dynamic v) {
                        final s = (v ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
                        if (s.isEmpty) return '₦0';
                        final digits = s.split('');
                        final out = <String>[];
                        for (var i = 0; i < digits.length; i++) {
                          final revIndex = digits.length - 1 - i;
                          out.add(digits[revIndex]);
                          if ((i + 1) % 3 == 0 && revIndex != 0) out.add(',');
                        }
                        return '₦' + out.reversed.join();
                      }

                      String _fmtLocation(String city, String state) {
                        final c = city.trim();
                        final s2 = state.trim();
                        if (c.isEmpty && s2.isEmpty) return 'Location not set';
                        if (c.isEmpty) return s2;
                        if (s2.isEmpty) return c;
                        return '$c, $s2';
                      }

                      final priceText = _fmtNaira(m['nightly_price'] ?? m['price']);
                      final locText = _fmtLocation(city, state);
                      final bedsText = beds.trim().isEmpty ? '-' : beds;
                      final bathsText = baths.trim().isEmpty ? '-' : baths;


                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            if (id == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Shortlet details not available yet.')),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ShortletDetailScreen(
                                  shortlet: Map<String, dynamic>.from(m),
                                ),
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
                                    child: const Icon(Icons.apartment_outlined, size: 36, color: Color(0xFF60A5FA)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 4),
                                        Text(locText, style: TextStyle(color: Colors.grey.shade600)),
                                        const SizedBox(height: 6),
                                        Text('Beds: $bedsText  •  Baths: $bathsText', style: const TextStyle(fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('₦$price', style: const TextStyle(fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 2),
                                      const Text('/ night', style: TextStyle(fontSize: 12)),
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
