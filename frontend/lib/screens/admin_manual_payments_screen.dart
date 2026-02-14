import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';
import '../utils/formatters.dart';
import 'admin_manual_payment_detail_screen.dart';

class AdminManualPaymentsScreen extends StatefulWidget {
  const AdminManualPaymentsScreen({super.key});

  @override
  State<AdminManualPaymentsScreen> createState() =>
      _AdminManualPaymentsScreenState();
}

class _AdminManualPaymentsScreenState extends State<AdminManualPaymentsScreen> {
  final AdminAutopilotService _svc = AdminAutopilotService();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  String _status = 'manual_pending';
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
      final rows = await _svc.listManualPayments(
        q: _searchCtrl.text,
        status: _status,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
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

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green.shade100;
      case 'manual_pending':
      case 'initialized':
        return Colors.orange.shade100;
      case 'cancelled':
      case 'failed':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade200;
    }
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Payments Queue'),
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
                      labelText: 'Search reference/order/buyer',
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _load, child: const Text('Search')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final status in const [
                  'manual_pending',
                  'paid',
                  'cancelled',
                  'failed',
                  'all',
                ])
                  ChoiceChip(
                    label: Text(status),
                    selected: _status == status,
                    onSelected: (_) {
                      setState(() => _status = status);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(
                            child: Text('No manual payment intents found.'),
                          )
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, idx) {
                              final item = _items[idx];
                              final intentId = int.tryParse(
                                      (item['payment_intent_id'] ?? '')
                                          .toString()) ??
                                  int.tryParse(
                                      (item['intent_id'] ?? '').toString()) ??
                                  0;
                              final orderId =
                                  (item['order_id'] ?? '-').toString();
                              final reference =
                                  (item['reference'] ?? '').toString();
                              final buyerEmail =
                                  (item['buyer_email'] ?? '').toString();
                              final status = (item['status'] ?? '').toString();
                              final amount = item['amount'];
                              final proofSubmitted =
                                  item['proof_submitted'] == true;

                              return ListTile(
                                onTap: intentId > 0
                                    ? () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AdminManualPaymentDetailScreen(
                                                    paymentIntentId: intentId),
                                          ),
                                        );
                                        if (!mounted) return;
                                        _load();
                                      }
                                    : null,
                                title: Text('Order #$orderId • $reference'),
                                subtitle: Text(
                                  '$buyerEmail\nAmount: ${formatNaira(amount)}',
                                ),
                                isThreeLine: true,
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    _statusChip(status),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          proofSubmitted
                                              ? Icons.verified_outlined
                                              : Icons.info_outline,
                                          size: 16,
                                          color: proofSubmitted
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          proofSubmitted ? 'Proof' : 'No proof',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ],
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
