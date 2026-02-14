import 'package:flutter/material.dart';

import '../services/payout_recipient_service.dart';

class PayoutRecipientScreen extends StatefulWidget {
  const PayoutRecipientScreen({super.key});

  @override
  State<PayoutRecipientScreen> createState() => _PayoutRecipientScreenState();
}

class _PayoutRecipientScreenState extends State<PayoutRecipientScreen> {
  final _svc = PayoutRecipientService();
  final _code = TextEditingController();
  bool _loading = true;
  String _current = "";

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _svc.getRecipient();
    if (!mounted) return;
    final rec = r['recipient'];
    setState(() {
      _current = rec is Map ? (rec['recipient_code'] ?? '').toString() : "";
      _loading = false;
    });
  }

  Future<void> _save() async {
    final v = _code.text.trim();
    if (v.isEmpty) {
      _toast("Paste recipient code");
      return;
    }
    setState(() => _loading = true);
    await _svc.setRecipient(recipientCode: v);
    _code.clear();
    await _load();
    _toast("Saved recipient code");
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Payout Recipient")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Current: ${_current.isEmpty ? 'Not set' : _current}"),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Paystack recipient_code",
                      helperText: "Paste your provider recipient_code here.",
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text("Save"),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
