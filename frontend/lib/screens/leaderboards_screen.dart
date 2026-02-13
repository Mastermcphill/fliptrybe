import 'package:flutter/material.dart';

import '../constants/ng_states.dart';
import '../services/leaderboard_service.dart';
import 'merchant_detail_screen.dart';

class LeaderboardsScreen extends StatefulWidget {
  const LeaderboardsScreen({super.key});

  @override
  State<LeaderboardsScreen> createState() => _LeaderboardsScreenState();
}

class _LeaderboardsScreenState extends State<LeaderboardsScreen> {
  final _svc = LeaderboardService();
  late Future<List<dynamic>> _ranked;
  bool _byState = false;
  String _state = allNigeriaLabel;

  @override
  void initState() {
    super.initState();
    _ranked = _loadRanked();
  }

  Future<List<dynamic>> _loadRanked() {
    final selectedState = _byState && _state != allNigeriaLabel ? _state : null;
    return _svc.ranked(state: selectedState, limit: 50);
  }

  void _reload() {
    setState(() {
      _ranked = _loadRanked();
    });
  }

  Widget _merchantTile(Map<String, dynamic> m) {
    final uid = int.tryParse((m['user_id'] ?? '').toString()) ?? 0;
    final rank = int.tryParse((m['rank'] ?? '').toString()) ?? 0;
    final name = (m['shop_name'] ?? '').toString().trim().isEmpty ? 'Merchant $uid' : (m['shop_name'] ?? '').toString();
    final badge = (m['badge'] ?? 'New').toString();
    final score = (m['score'] ?? 0).toString();
    final city = (m['city'] ?? '').toString();
    final state = (m['state'] ?? '').toString();
    final orders = (m['total_orders'] ?? 0).toString();
    final deliveries = (m['successful_deliveries'] ?? 0).toString();
    final rating = (m['avg_rating'] ?? 0).toString();
    final profileImage = (m['profile_image_url'] ?? '').toString().trim();

    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFE2E8F0),
              backgroundImage:
                  profileImage.isNotEmpty ? NetworkImage(profileImage) : null,
              child: profileImage.isNotEmpty
                  ? null
                  : Text(name.isEmpty ? 'M' : name[0].toUpperCase()),
            ),
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  rank > 0 ? '$rank' : '#',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(
        '$badge  |  Score $score\n$city, $state\nOrders: $orders  Deliveries: $deliveries  Rating: $rating',
      ),
      isThreeLine: true,
      onTap: uid > 0 ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantDetailScreen(userId: uid))) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboards'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Nationwide'),
                  selected: !_byState,
                  onSelected: (v) {
                    if (!v) return;
                    setState(() {
                      _byState = false;
                      _state = allNigeriaLabel;
                      _ranked = _loadRanked();
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('By State'),
                  selected: _byState,
                  onSelected: (v) {
                    if (!v) return;
                    setState(() {
                      _byState = true;
                      _ranked = _loadRanked();
                    });
                  },
                ),
              ],
            ),
          ),
          if (_byState)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: DropdownButtonFormField<String>(
                initialValue: _state,
                decoration: const InputDecoration(
                  labelText: 'State',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: allNigeriaLabel, child: Text(allNigeriaLabel)),
                  ...nigeriaStates.map(
                    (s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(displayState(s)),
                    ),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _state = v ?? allNigeriaLabel;
                    _ranked = _loadRanked();
                  });
                },
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<dynamic>>(
                future: _ranked,
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
                        Center(child: Text('No leaderboard entries found for this scope.')),
                      ],
                    );
                  }
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final raw = items[i];
                      if (raw is! Map) return const SizedBox.shrink();
                      return Card(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: _merchantTile(Map<String, dynamic>.from(raw)),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
