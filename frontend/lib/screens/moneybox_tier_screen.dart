import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';
import 'kyc_demo_screen.dart';

class MoneyBoxTierScreen extends StatefulWidget {
  const MoneyBoxTierScreen({super.key});

  @override
  State<MoneyBoxTierScreen> createState() => _MoneyBoxTierScreenState();
}

class _MoneyBoxTierScreenState extends State<MoneyBoxTierScreen> {
  final _svc = MoneyBoxService();
  bool _loading = false;
  late Future<Map<String, dynamic>> _statusFuture;
  int _currentTier = 1;
  String _moneyboxStatus = 'none';

  final _tiers = const [
    {'tier': 1, 'label': 'Tier 1', 'duration': 'Up to 30 days', 'bonus': '0% bonus'},
    {'tier': 2, 'label': 'Tier 2', 'duration': '4 months', 'bonus': '3% bonus'},
    {'tier': 3, 'label': 'Tier 3', 'duration': '7 months', 'bonus': '8% bonus'},
    {'tier': 4, 'label': 'Tier 4', 'duration': '11 months', 'bonus': '15% bonus'},
  ];

  @override
  void initState() {
    super.initState();
    _statusFuture = _loadStatus();
  }

  Future<Map<String, dynamic>> _loadStatus() async {
    final data = await _svc.status();
    _currentTier = int.tryParse((data['tier'] ?? '1').toString()) ?? 1;
    _moneyboxStatus = (data['status'] ?? 'none').toString().toLowerCase();
    return data;
  }

  bool _isTierLocked(int tier) {
    if (_moneyboxStatus == 'none' || _moneyboxStatus == 'closed') {
      return tier != 1;
    }
    return tier > (_currentTier + 1);
  }

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
        await showEmailVerificationRequiredDialog(
          context,
          message: showMsg,
          onRetry: () => _open(tier),
        );
        return;
      }
      if (ApiService.isTierOrKycRestriction(res) || ApiService.isTierOrKycRestriction(showMsg)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showMsg),
            action: SnackBarAction(
              label: 'Verify ID',
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const KycDemoScreen()));
              },
            ),
          ),
        );
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
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statusFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _tiers.length + 1,
            itemBuilder: (_, i) {
              if (i == 0) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text('Current tier: $_currentTier'),
                    subtitle: Text('MoneyBox status: ${_moneyboxStatus.toUpperCase()}'),
                  ),
                );
              }

              final t = _tiers[i - 1];
              final tierValue = t['tier'] as int;
              final locked = _isTierLocked(tierValue);
              final isCurrent = tierValue == _currentTier;
              final lockText = isCurrent
                  ? 'Current tier'
                  : locked
                      ? 'Locked until you move up'
                      : 'Available';

              return Card(
                child: ListTile(
                  title: Text('${t['label']} - ${t['duration']}'),
                  subtitle: Text('${t['bonus']} | $lockText'),
                  trailing: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(locked ? Icons.lock_outline : Icons.arrow_forward),
                  onTap: (_loading || locked || isCurrent) ? null : () => _open(tierValue),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
