import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/payment_service.dart';
import '../utils/formatters.dart';
import 'order_detail_screen.dart';

class ManualPaymentInstructionsScreen extends StatefulWidget {
  const ManualPaymentInstructionsScreen({
    super.key,
    required this.orderId,
    required this.amount,
    required this.reference,
    this.paymentIntentId,
    this.initialInstructions,
  });

  final int orderId;
  final double amount;
  final String reference;
  final int? paymentIntentId;
  final Map<String, dynamic>? initialInstructions;

  @override
  State<ManualPaymentInstructionsScreen> createState() =>
      _ManualPaymentInstructionsScreenState();
}

class _ManualPaymentInstructionsScreenState
    extends State<ManualPaymentInstructionsScreen> {
  final PaymentService _service = PaymentService();
  final TextEditingController _txnRefCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  bool _navigatedOnPaid = false;
  String? _error;

  int? _paymentIntentId;
  String _paymentStatus = 'manual_pending';
  Map<String, dynamic> _instructions = const <String, dynamic>{};

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _paymentIntentId = widget.paymentIntentId;
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _txnRefCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.initialInstructions != null &&
          widget.initialInstructions!.isNotEmpty) {
        _instructions = Map<String, dynamic>.from(widget.initialInstructions!);
      } else {
        final resp = await _service.manualInstructions();
        if (resp['instructions'] is Map) {
          _instructions = Map<String, dynamic>.from(
              resp['instructions'] as Map<dynamic, dynamic>);
        }
      }
      await _refreshStatus();
      _startPolling();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load payment instructions: $e';
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshStatus();
    });
  }

  Future<void> _refreshStatus() async {
    final status = await _service.status(orderId: widget.orderId);
    final paymentStatus = (status['payment_status'] ?? 'unknown').toString();
    final paymentIntentRaw = status['payment_intent_id'];
    final parsedIntent = paymentIntentRaw is int
        ? paymentIntentRaw
        : int.tryParse((paymentIntentRaw ?? '').toString());
    if (!mounted) return;
    setState(() {
      _paymentStatus = paymentStatus;
      if (parsedIntent != null) {
        _paymentIntentId = parsedIntent;
      }
    });

    if (_paymentStatus == 'paid' && !_navigatedOnPaid) {
      _navigatedOnPaid = true;
      _pollTimer?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment confirmed.')),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: widget.orderId),
        ),
      );
    }
  }

  Future<void> _copyReference() async {
    await Clipboard.setData(ClipboardData(text: widget.reference));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reference copied.')),
    );
  }

  Future<void> _submitProof() async {
    final intentId = _paymentIntentId;
    if (intentId == null || intentId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Payment intent not available yet. Please refresh status.')),
      );
      return;
    }
    final txn = _txnRefCtrl.text.trim();
    final note = _noteCtrl.text.trim();
    if (txn.isEmpty && note.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter bank transaction reference or note.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final resp = await _service.submitManualProof(
        paymentIntentId: intentId,
        bankTxnReference: txn,
        note: note,
      );
      if (!mounted) return;
      if (resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Payment proof submitted. Awaiting admin confirmation.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text((resp['message'] ??
                      resp['error'] ??
                      'Proof submission failed')
                  .toString())),
        );
      }
      await _refreshStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proof submission failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Color _statusColor(String value) {
    switch (value.toLowerCase()) {
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountName = (_instructions['account_name'] ?? '').toString();
    final accountNumber = (_instructions['account_number'] ?? '').toString();
    final bankName = (_instructions['bank_name'] ?? '').toString();
    final note = (_instructions['note'] ?? '').toString();
    final slaMinutes = (_instructions['sla_minutes'] ?? 360).toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Payment'),
        actions: [
          IconButton(
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _statusColor(_paymentStatus),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Payment status: ${_paymentStatus.toUpperCase()}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Transfer Instructions',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            _infoRow('Amount', formatNaira(widget.amount)),
                            _infoRow('Bank', bankName),
                            _infoRow('Account Name', accountName),
                            _infoRow('Account Number', accountNumber),
                            _infoRow('Reference', widget.reference),
                            if (note.trim().isNotEmpty) _infoRow('Note', note),
                            _infoRow('SLA', '$slaMinutes minutes'),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _copyReference,
                                  icon: const Icon(Icons.copy_all_outlined),
                                  label: const Text('Copy reference'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _refreshStatus,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Refresh status'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'I Have Paid',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _txnRefCtrl,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Bank transaction reference (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Note (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submitProof,
                      child: Text(_submitting
                          ? 'Submitting...'
                          : 'Submit payment proof'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Do not transfer funds without including the reference. Confirmation is completed after admin verification.',
                    ),
                  ],
                ),
    );
  }
}
