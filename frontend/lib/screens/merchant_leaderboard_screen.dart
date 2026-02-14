import 'package:flutter/material.dart';

import '../services/merchant_service.dart';

class MerchantLeaderboardScreen extends StatefulWidget {
  const MerchantLeaderboardScreen({super.key});

  @override
  State<MerchantLeaderboardScreen> createState() =>
      _MerchantLeaderboardScreenState();
}

class _MerchantLeaderboardScreenState extends State<MerchantLeaderboardScreen> {
  final _svc = MerchantService();
  bool _loading = true;
  List<dynamic> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.getLeaderboard();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Top Merchants"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_rows.isEmpty)
              ? const Center(child: Text("No merchants yet."))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final raw = _rows[i];
                    if (raw is! Map) return const SizedBox.shrink();
                    final m = Map<String, dynamic>.from(raw);
                    final rank = i + 1;
                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: ListTile(
                        leading: CircleAvatar(child: Text("$rank")),
                        title: Text(m["name"]?.toString() ?? "Merchant",
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(
                            "Score: ${m['score']}  • Orders: ${m['orders']}  • Listings: ${m['listings']}"),
                        trailing: Text("₦${m['revenue_gross']}",
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    );
                  },
                ),
    );
  }
}
