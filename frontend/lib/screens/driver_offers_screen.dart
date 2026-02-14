import 'package:flutter/material.dart';

import '../services/driver_offer_service.dart';

class DriverOffersScreen extends StatefulWidget {
  const DriverOffersScreen({super.key});

  @override
  State<DriverOffersScreen> createState() => _DriverOffersScreenState();
}

class _DriverOffersScreenState extends State<DriverOffersScreen> {
  final _svc = DriverOfferService();
  bool _loading = true;
  List<dynamic> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.myOffers();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _accept(int id) async {
    await _svc.accept(id);
    await _load();
  }

  Future<void> _reject(int id) async {
    await _svc.reject(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Driver Offers"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _rows[i] is Map
                    ? Map<String, dynamic>.from(_rows[i])
                    : <String, dynamic>{};
                final status = (r['status'] ?? '').toString();
                final id = int.tryParse((r['id'] ?? '0').toString()) ?? 0;
                return ListTile(
                  title: Text("Order #${r['order_id']}"),
                  subtitle: Text("Status: $status"),
                  trailing: status == "offered"
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                                onPressed: () => _accept(id),
                                icon: const Icon(Icons.check_circle_outline)),
                            IconButton(
                                onPressed: () => _reject(id),
                                icon: const Icon(Icons.cancel_outlined)),
                          ],
                        )
                      : null,
                );
              },
            ),
    );
  }
}
