import 'package:flutter/material.dart';

import '../services/merchant_service.dart';

class MerchantFollowersScreen extends StatefulWidget {
  const MerchantFollowersScreen({super.key});

  @override
  State<MerchantFollowersScreen> createState() =>
      _MerchantFollowersScreenState();
}

class _MerchantFollowersScreenState extends State<MerchantFollowersScreen> {
  final _svc = MerchantService();
  bool _loading = true;
  String? _error;
  int _count = 0;
  List<Map<String, dynamic>> _items = const [];

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
      final values = await Future.wait([
        _svc.merchantFollowersCount(),
        _svc.merchantFollowers(limit: 100),
      ]);
      if (!mounted) return;
      final countMap = Map<String, dynamic>.from(values[0] as Map);
      setState(() {
        _count = int.tryParse((countMap['followers'] ?? 0).toString()) ?? 0;
        _items = values[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load followers: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Merchant Followers'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  children: [
                    ListTile(
                      title: const Text('Total followers'),
                      trailing: Text(
                        '$_count',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Divider(height: 1),
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No followers yet.'),
                      )
                    else
                      ..._items.map((item) {
                        final name = (item['name'] ?? 'Follower').toString();
                        final email = (item['email'] ?? '').toString();
                        final followedAt =
                            (item['followed_at'] ?? '').toString();
                        return ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: Text(name),
                          subtitle: Text('$email\nFollowed: $followedAt'),
                          isThreeLine: true,
                        );
                      }),
                  ],
                ),
    );
  }
}
