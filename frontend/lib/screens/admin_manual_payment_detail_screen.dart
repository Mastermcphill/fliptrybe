import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';
import '../utils/formatters.dart';
import 'admin_order_timeline_screen.dart';

class AdminManualPaymentDetailScreen extends StatefulWidget {
  const AdminManualPaymentDetailScreen({
    super.key,
    required this.paymentIntentId,
  });

  final int paymentIntentId;

  @override
  State<AdminManualPaymentDetailScreen> createState() =>
      _AdminManualPaymentDetailScreenState();
}

class _AdminManualPaymentDetailScreenState
    extends State<AdminManualPaymentDetailScreen> {
  final AdminAutopilotService _svc = AdminAutopilotService();
  final TextEditingController _bankTxnCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _rejectReasonCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _detail = const <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bankTxnCtrl.dispose();
    _noteCtrl.dispose();
    _rejectReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp = await _svc.getManualPaymentDetails(
        paymentIntentId: widget.paymentIntentId,
      );
      if (!mounted) return;
      if (resp['ok'] == true) {
        setState(() {
          _detail = resp;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error =
              (resp['message'] ?? resp['error'] ?? 'Failed to load details')
                  .toString();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load manual payment details: $e';
      });
    }
  }

  Future<void> _markPaid() async {
    if (_saving) return;
    final intent = (_detail['intent'] is Map)
        ? Map<String, dynamic>.from(_detail['intent'] as Map)
        : <String, dynamic>{};
    final orderId = int.tryParse((intent['order_id'] ?? '').toString()) ?? 0;
    final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirm mark paid'),
            content:
                Text('Mark payment intent #${widget.paymentIntentId} as paid?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    setState(() => _saving = true);
    try {
      final resp = await _svc.markManualPaid(
        paymentIntentId: widget.paymentIntentId,
        bankTxnReference: _bankTxnCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
      );
      if (!mounted) return;
      if (resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resp['idempotent'] == true
                ? 'Already marked paid.'
                : 'Payment marked paid.'),
          ),
        );
        await _load();
        final resolvedOrderId =
            int.tryParse((resp['order_id'] ?? orderId).toString()) ?? orderId;
        if (resolvedOrderId > 0 && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  AdminOrderTimelineScreen(orderId: resolvedOrderId),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                (resp['message'] ?? resp['error'] ?? 'Mark paid failed')
                    .toString()),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Mark paid failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reject() async {
    if (_saving) return;
    final reason = _rejectReasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reject reason is required.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final resp = await _svc.rejectManualPayment(
        paymentIntentId: widget.paymentIntentId,
        reason: reason,
      );
      if (!mounted) return;
      if (resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manual payment rejected.')),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  (resp['message'] ?? resp['error'] ?? 'Reject failed')
                      .toString())),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intent = (_detail['intent'] is Map)
        ? Map<String, dynamic>.from(_detail['intent'] as Map)
        : <String, dynamic>{};
    final order = (_detail['order'] is Map)
        ? Map<String, dynamic>.from(_detail['order'] as Map)
        : <String, dynamic>{};
    final proof = (_detail['proof'] is Map)
        ? Map<String, dynamic>.from(_detail['proof'] as Map)
        : <String, dynamic>{};
    final transitions = (_detail['transitions'] is List)
        ? List<Map<String, dynamic>>.from(
            (_detail['transitions'] as List)
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row)),
          )
        : <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('Manual Payment #${widget.paymentIntentId}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Intent',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            _kv('Status', (intent['status'] ?? '').toString()),
                            _kv('Reference',
                                (intent['reference'] ?? '').toString()),
                            _kv('Order ID',
                                (intent['order_id'] ?? '').toString()),
                            _kv('Amount', formatNaira(intent['amount'])),
                            _kv('Proof submitted',
                                (proof['submitted'] == true).toString()),
                            _kv('Bank txn ref',
                                (proof['bank_txn_reference'] ?? '').toString()),
                            _kv('Proof note', (proof['note'] ?? '').toString()),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Actions',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _bankTxnCtrl,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Bank transaction reference',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _noteCtrl,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Admin note',
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _saving ? null : _markPaid,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Mark paid'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _rejectReasonCtrl,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Reject reason',
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _reject,
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('Reject payment'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if ((order['id'] ?? 0) != 0)
                      OutlinedButton.icon(
                        onPressed: () {
                          final orderId =
                              int.tryParse((order['id'] ?? '').toString()) ?? 0;
                          if (orderId <= 0) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdminOrderTimelineScreen(orderId: orderId),
                            ),
                          );
                        },
                        icon: const Icon(Icons.timeline_outlined),
                        label: const Text('Open order timeline'),
                      ),
                    const SizedBox(height: 12),
                    const Text('Transition History',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (transitions.isEmpty)
                      const Text('No transitions recorded.')
                    else
                      ...transitions.map(
                        (row) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.swap_horiz_outlined),
                          title: Text(
                            '${row['from_status'] ?? ''} -> ${row['to_status'] ?? ''}',
                          ),
                          subtitle: Text(
                            '${row['created_at'] ?? ''}\n${row['reason'] ?? ''}',
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
