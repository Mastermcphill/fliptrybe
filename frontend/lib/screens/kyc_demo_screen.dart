import 'package:flutter/material.dart';

import '../services/kyc_service.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _svc = KycService();
  late Future<Map<String, dynamic>> _kyc;

  final _nameCtrl = TextEditingController();
  final _idNumCtrl = TextEditingController();
  String _idType = 'nin';

  @override
  void initState() {
    super.initState();
    _kyc = _svc.status();
  }

  void _reload() {
    setState(() => _kyc = _svc.status());
  }

  Color _statusColor(String s) {
    s = s.toLowerCase();
    if (s == 'verified') return Colors.green;
    if (s == 'pending') return Colors.orange;
    if (s == 'rejected') return Colors.red;
    return Colors.grey;
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final num = _idNumCtrl.text.trim();
    if (name.isEmpty || num.isEmpty) return;

    final res =
        await _svc.submit(fullName: name, idType: _idType, idNumber: num);
    if (!mounted) return;
    if (res != null) {
      _reload();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('KYC submitted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ID Verification'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _kyc,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final kyc = snap.data ?? <String, dynamic>{};
          final status = (kyc['status'] ?? 'unverified').toString();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.verified_user, color: _statusColor(status)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text('Status: $status',
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Full name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _idType,
                decoration: const InputDecoration(
                    labelText: 'ID type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'nin', child: Text('NIN')),
                  DropdownMenuItem(value: 'bvn', child: Text('BVN')),
                  DropdownMenuItem(value: 'passport', child: Text('Passport')),
                  DropdownMenuItem(
                      value: 'drivers_license',
                      child: Text("Driver's License")),
                ],
                onChanged: (v) => setState(() => _idType = v ?? 'nin'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _idNumCtrl,
                decoration: const InputDecoration(
                    labelText: 'ID number', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Submit KYC'),
                ),
              ),
              const SizedBox(height: 12),
              if ((kyc['note'] ?? '').toString().trim().isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text((kyc['note'] ?? '').toString()),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'Verify your identity to unlock withdrawals and higher MoneyBox tiers.',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          );
        },
      ),
    );
  }
}

@Deprecated('Use KycScreen instead.')
class KycDemoScreen extends KycScreen {
  const KycDemoScreen({super.key});
}
