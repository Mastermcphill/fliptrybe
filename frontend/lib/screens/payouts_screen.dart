import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import '../services/bank_store.dart';
import '../services/api_service.dart';

class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

class _PayoutsScreenState extends State<PayoutsScreen> {
  final _svc = WalletService();
  final _store = BankStore();
  bool _remember = true;
  bool _sendingVerify = false;

  final _amount = TextEditingController(text: '5000');
  final _bank = TextEditingController(text: 'GTBank');
  final _acctNo = TextEditingController(text: '0123456789');
  final _acctName = TextEditingController(text: 'Omotunde Oni');

  bool _loading = true;
  List<dynamic> _rows = const [];

  bool _isVerifyMessage(String msg) {
    final m = msg.toLowerCase();
    return m.contains('verify your email') || m.contains('email verification required');
  }

  Future<void> _showVerifyDialog(String msg) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Email verification required'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: _sendingVerify
                  ? null
                  : () async {
                      try {
                        _sendingVerify = true;
                        await ApiService.verifySend();
                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Verification email sent')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Resend failed: $e')),
                        );
                      } finally {
                        _sendingVerify = false;
                      }
                    },
              child: const Text('Resend verification'),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _hydrateBank();
    _load();
  }

  Future<void> _hydrateBank() async {
    final data = await _store.load();
    if (!mounted) return;
    if ((data['bank_name'] ?? '').isNotEmpty) _bank.text = data['bank_name']!;
    if ((data['account_number'] ?? '').isNotEmpty) _acctNo.text = data['account_number']!;
    if ((data['account_name'] ?? '').isNotEmpty) _acctName.text = data['account_name']!;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.payouts();
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _request() async {
    final amt = double.tryParse(_amount.text.trim()) ?? 0;
    if (amt <= 0) return;

    if (_remember) {
      await _store.save(
        bankName: _bank.text.trim(),
        accountNumber: _acctNo.text.trim(),
        accountName: _acctName.text.trim(),
      );
    }

    final res = await _svc.requestPayout(
      amount: amt,
      bankName: _bank.text,
      accountNumber: _acctNo.text,
      accountName: _acctName.text,
    );

    if (!mounted) return;
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? (ok ? 'Payout requested' : 'Request failed')).toString();
    if (!ok && _isVerifyMessage(msg)) {
      await _showVerifyDialog(msg);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (ok) _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _bank.dispose();
    _acctNo.dispose();
    _acctName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payouts'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Request payout', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bank,
                  decoration: const InputDecoration(labelText: 'Bank name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _acctNo,
                  decoration: const InputDecoration(labelText: 'Account number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _acctName,
                  decoration: const InputDecoration(labelText: 'Account name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _request,
                  icon: const Icon(Icons.send),
                  label: const Text('Request'),
                ),
                const Divider(height: 28),
                const Text('History', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const Text('No payout requests yet.')
                else
                  ..._rows.whereType<Map>().map((raw) {
                    final m = Map<String, dynamic>.from(raw as Map);
                    return Card(
                      child: ListTile(
                        title: Text('NGN ${m['amount'] ?? 0} - ${m['status'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.w900)),
                        subtitle: Text(
                          '${m['bank_name'] ?? ''} - ${m['account_number'] ?? ''}\n${m['account_name'] ?? ''}',
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
