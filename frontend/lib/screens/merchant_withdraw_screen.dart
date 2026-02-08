import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import '../services/api_service.dart';

class MerchantWithdrawScreen extends StatefulWidget {
  const MerchantWithdrawScreen({super.key});

  @override
  State<MerchantWithdrawScreen> createState() => _MerchantWithdrawScreenState();
}

class _MerchantWithdrawScreenState extends State<MerchantWithdrawScreen> {
  final _svc = WalletService();

  final _amount = TextEditingController();
  final _bankName = TextEditingController(text: "GTBank");
  final _acctNo = TextEditingController();
  final _acctName = TextEditingController();
  bool _loading = false;
  bool _sendingVerify = false;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
                        _toast('Verification email sent');
                      } catch (e) {
                        _toast('Resend failed: $e');
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

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim()) ?? 0.0;
    if (amt <= 0) {
      _toast("Enter amount");
      return;
    }
    if (_acctNo.text.trim().length < 8) {
      _toast("Enter valid account number");
      return;
    }

    setState(() => _loading = true);
    final res = await _svc.requestPayout(
      amount: amt,
      bankName: _bankName.text.trim(),
      accountNumber: _acctNo.text.trim(),
      accountName: _acctName.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? (ok ? 'Payout request sent' : 'Failed')).toString();
    if (!ok && _isVerifyMessage(msg)) {
      await _showVerifyDialog(msg);
      return;
    }
    _toast(msg);
    if (ok) Navigator.pop(context);
  }

  @override
  void dispose() {
    _amount.dispose();
    _bankName.dispose();
    _acctNo.dispose();
    _acctName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Withdraw / Payout Request")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text("Request a withdrawal to your bank account.", style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(controller: _amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Amount (₦)", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _bankName, decoration: const InputDecoration(labelText: "Bank Name", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _acctNo, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Account Number", border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: _acctName, decoration: const InputDecoration(labelText: "Account Name (optional)", border: OutlineInputBorder())),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
            label: const Text("Submit Request"),
          )
        ],
      ),
    );
  }
}

