import 'package:flutter/material.dart';

import '../services/merchant_service.dart';
import 'merchant_detail_screen.dart';

class MerchantsScreen extends StatefulWidget {
  const MerchantsScreen({super.key});

  @override
  State<MerchantsScreen> createState() => _MerchantsScreenState();
}

class _MerchantsScreenState extends State<MerchantsScreen> {
  final _svc = MerchantService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.topMerchants(limit: 30);
  }

  Widget _badge(String b) {
    Color c = Colors.grey.shade600;
    if (b == "Elite") c = Colors.purple;
    if (b == "Trusted") c = Colors.green;
    if (b == "Rising") c = Colors.blue;
    if (b == "Suspended") c = Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(b, style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Top Merchants")),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _future = _svc.topMerchants(limit: 30));
        },
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text("No merchants yet.")),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final raw = items[i];
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw);
                final name = (m['shop_name'] ?? '').toString().trim().isEmpty ? "Merchant ${m['user_id']}" : (m['shop_name'] ?? '').toString();
                final city = (m['city'] ?? '').toString();
                final state = (m['state'] ?? '').toString();
                final badge = (m['badge'] ?? 'New').toString();
                final score = (m['score'] ?? 0).toString();
                final featured = m['is_featured'] == true;

                return InkWell(
                  onTap: () {
                    final uid = int.tryParse((m['user_id'] ?? '').toString()) ?? 0;
                    if (uid > 0) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantDetailScreen(userId: uid)));
                    }
                  },
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : "M"),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                                    ),
                                    if (featured)
                                      const Icon(Icons.star, size: 18),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text("$city, $state", style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _badge(badge),
                                    const SizedBox(width: 10),
                                    Text("Score: $score", style: const TextStyle(fontWeight: FontWeight.w800)),
                                  ],
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
