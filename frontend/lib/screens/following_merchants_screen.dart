import 'package:flutter/material.dart';

import '../services/merchant_service.dart';
import 'merchant_detail_screen.dart';

class FollowingMerchantsScreen extends StatefulWidget {
  const FollowingMerchantsScreen({super.key});

  @override
  State<FollowingMerchantsScreen> createState() =>
      _FollowingMerchantsScreenState();
}

class _FollowingMerchantsScreenState extends State<FollowingMerchantsScreen> {
  final _svc = MerchantService();
  bool _loading = true;
  String? _error;
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
      final rows = await _svc.myFollowingMerchants(limit: 100);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load following merchants: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Following Merchants'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(
                      child: Text('You are not following any merchants yet.'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        final merchantId = int.tryParse(
                                (item['merchant_id'] ?? '').toString()) ??
                            0;
                        final name = (item['name'] ?? 'Merchant').toString();
                        final email = (item['email'] ?? '').toString();
                        return ListTile(
                          title: Text(name),
                          subtitle: Text(email),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: merchantId <= 0
                              ? null
                              : () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => MerchantDetailScreen(
                                          userId: merchantId),
                                    ),
                                  );
                                },
                        );
                      },
                    ),
    );
  }
}
