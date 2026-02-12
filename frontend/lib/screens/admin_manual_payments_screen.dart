import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';

class AdminManualPaymentsScreen extends StatefulWidget {
  const AdminManualPaymentsScreen({super.key});

  @override
  State<AdminManualPaymentsScreen> createState() =>
      _AdminManualPaymentsScreenState();
}

class _AdminManualPaymentsScreenState extends State<AdminManualPaymentsScreen> {
  final _svc = AdminAutopilotService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await _svc.listManualPayments(q: _searchCtrl.text, limit: 100);
      if (!mounted) return;
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load manual payments: $e';
      });
    }
  }

  Future<void> _markPaid(Map<String, dynamic> item) async {
    final orderId = int.tryParse((item['order_id'] ?? '').toString()) ?? 0;
    if (orderId <= 0 || _saving) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Mark payment as paid'),
            content: Text('Confirm manual payment for order #$orderId?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final res = await _svc.markManualPaid(orderId: orderId, note: 'admin-ui');
      if (!mounted) return;
      final success = res['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(success
                ? 'Order #$orderId marked paid.'
                : (res['message'] ?? res['error'] ?? 'Failed').toString())),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Mark paid failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Payments'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Search order/reference',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _load, child: const Text('Search')),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(
                            child: Text('No pending manual payments.'))
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final item = _items[idx];
                              final orderId =
                                  (item['order_id'] ?? '-').toString();
                              final reference =
                                  (item['reference'] ?? '').toString();
                              final amount = (item['amount'] ?? 0).toString();
                              final buyerEmail =
                                  (item['buyer_email'] ?? '').toString();
                              return ListTile(
                                title: Text('Order #$orderId'),
                                subtitle: Text(
                                    'Reference: $reference\nBuyer: $buyerEmail\nAmount: ₦$amount'),
                                isThreeLine: true,
                                trailing: ElevatedButton(
                                  onPressed:
                                      _saving ? null : () => _markPaid(item),
                                  child: const Text('Mark paid'),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
