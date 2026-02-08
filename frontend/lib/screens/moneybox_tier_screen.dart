import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';

class MoneyBoxTierScreen extends StatefulWidget {
  const MoneyBoxTierScreen({super.key});

  @override
  State<MoneyBoxTierScreen> createState() => _MoneyBoxTierScreenState();
}

class _MoneyBoxTierScreenState extends State<MoneyBoxTierScreen> {
  final _svc = MoneyBoxService();
  bool _loading = false;

  final _tiers = const [
    {'tier': 1, 'label': 'Tier 1', 'duration': 'Up to 30 days', 'bonus': '0% bonus'},
    {'tier': 2, 'label': 'Tier 2', 'duration': '4 months', 'bonus': '3% bonus'},
    {'tier': 3, 'label': 'Tier 3', 'duration': '7 months', 'bonus': '8% bonus'},
    {'tier': 4, 'label': 'Tier 4', 'duration': '11 months', 'bonus': '15% bonus'},
  ];

  Future<void> _open(int tier) async {
    if (_loading) return;
    setState(() => _loading = true);
    final res = await _svc.openTier(tier);
    if (!mounted) return;
    setState(() => _loading = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? '').toString();
    if (!ok) {
      final showMsg = msg.isNotEmpty ? msg : 'Request failed';
      if (ApiService.isEmailNotVerified(res) || ApiService.isEmailNotVerified(showMsg)) {
        await showEmailVerificationRequiredDialog(context, message: showMsg);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(showMsg)),
      );
      return;
    }
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Tier')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tiers.length,
        itemBuilder: (_, i) {
          final t = _tiers[i];
          return Card(
            child: ListTile(
              title: Text('${t['label']} • ${t['duration']}'),
              subtitle: Text((t['bonus'] ?? '').toString()),
              trailing: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.arrow_forward),
              onTap: _loading ? null : () => _open(t['tier'] as int),
            ),
          );
        },
      ),
    );
  }
}
