import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';

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
  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    if (!ok && (ApiService.isEmailNotVerified(res) || ApiService.isEmailNotVerified(msg))) {
      await showEmailVerificationRequiredDialog(context, message: msg);
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

