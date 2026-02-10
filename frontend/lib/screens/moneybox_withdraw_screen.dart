import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';

class MoneyBoxWithdrawScreen extends StatefulWidget {
  final Map<String, dynamic> status;

  const MoneyBoxWithdrawScreen({super.key, required this.status});

  @override
  State<MoneyBoxWithdrawScreen> createState() => _MoneyBoxWithdrawScreenState();
}

class _MoneyBoxWithdrawScreenState extends State<MoneyBoxWithdrawScreen> {
  final _svc = MoneyBoxService();
  bool _loading = false;

  double _penaltyRate() {
    final lockStart = widget.status['lock_start_at']?.toString();
    final autoOpen = widget.status['auto_open_at']?.toString();
    if (lockStart == null || autoOpen == null) return 0.0;
    try {
      final start = DateTime.parse(lockStart);
      final end = DateTime.parse(autoOpen);
      final now = DateTime.now();
      if (now.isAfter(end)) return 0.0;
      final total = end.difference(start).inSeconds;
      if (total <= 0) return 0.0;
      final elapsed = now.difference(start).inSeconds;
      final ratio = (elapsed / total).clamp(0.0, 1.0);
      if (ratio <= (1 / 3)) return 0.07;
      if (ratio <= (2 / 3)) return 0.05;
      return 0.02;
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> _withdrawAll() async {
    if (_loading) return;
    setState(() => _loading = true);
    final res = await _svc.withdraw();
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
          onRetry: _withdrawAll,
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
    final principal = double.tryParse(widget.status['principal_balance']?.toString() ?? '0') ?? 0;
    final bonus = double.tryParse(widget.status['projected_bonus']?.toString() ?? '0') ?? 0;
    final penaltyRate = _penaltyRate();
    final penalty = (principal * penaltyRate);
    final payout = (principal - penalty + bonus).clamp(0, double.infinity);

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Principal: ₦${principal.toStringAsFixed(2)}'),
            Text('Projected bonus: ₦${bonus.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text('Penalty rate: ${(penaltyRate * 100).toStringAsFixed(0)}%'),
            Text('Penalty estimate: ₦${penalty.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Text('Estimated payout: ₦${payout.toStringAsFixed(2)}'),
            const SizedBox(height: 6),
            const Text(
              'Early withdrawal voids your tier bonus.',
              style: TextStyle(color: Colors.grey),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _withdrawAll,
                child: Text(_loading ? 'Processing...' : 'Withdraw to Wallet'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
