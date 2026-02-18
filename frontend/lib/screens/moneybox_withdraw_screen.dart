import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/analytics_hooks.dart';
import '../services/moneybox_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ft_routes.dart';
import '../utils/role_gates.dart';
import '../utils/ui_feedback.dart';
import '../widgets/phone_verification_dialog.dart';
import 'kyc_screen.dart';
import 'money_action_receipt_screen.dart';

class MoneyBoxWithdrawScreen extends StatefulWidget {
  const MoneyBoxWithdrawScreen({super.key, required this.status});

  final Map<String, dynamic> status;

  @override
  State<MoneyBoxWithdrawScreen> createState() => _MoneyBoxWithdrawScreenState();
}

class _MoneyBoxWithdrawScreenState extends State<MoneyBoxWithdrawScreen> {
  final MoneyBoxService _svc = MoneyBoxService();
  bool _loading = false;

  double _penaltyRate() {
    final lockStart = widget.status['lock_start_at']?.toString();
    final autoOpen = widget.status['auto_open_at']?.toString();
    if (lockStart == null || autoOpen == null) return 0;
    try {
      final start = DateTime.parse(lockStart);
      final end = DateTime.parse(autoOpen);
      final now = DateTime.now();
      if (now.isAfter(end)) return 0;
      final total = end.difference(start).inSeconds;
      if (total <= 0) return 0;
      final elapsed = now.difference(start).inSeconds;
      final ratio = (elapsed / total).clamp(0.0, 1.0);
      if (ratio <= (1 / 3)) return 0.07;
      if (ratio <= (2 / 3)) return 0.05;
      return 0.02;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _withdrawAll() async {
    if (_loading) return;

    final profile = await ApiService.getProfile();
    final gate = RoleGates.forWithdraw(profile);
    final gateAllowed = await guardRestrictedAction(
      context,
      block: gate,
      authAction: 'withdraw earnings',
      onAllowed: () async {},
    );
    if (!gateAllowed || !mounted) return;

    final principal = double.tryParse(
            widget.status['principal_balance']?.toString() ?? '0') ??
        0;
    final bonus =
        double.tryParse(widget.status['projected_bonus']?.toString() ?? '0') ??
            0;
    final penaltyRate = _penaltyRate();
    final penalty = principal * penaltyRate;
    final payout =
        (principal - penalty + bonus).clamp(0.0, double.infinity).toDouble();

    final confirmed = await showMoneyConfirmationSheet(
      context,
      FTMoneyConfirmationPayload(
        title: 'Confirm MoneyBox withdrawal',
        amount: principal + bonus,
        fee: penalty,
        total: payout,
        destination: 'Wallet balance',
        actionLabel: 'Withdraw now',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    final res = await _svc.withdraw();
    if (!mounted) return;
    setState(() => _loading = false);

    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? '').toString();
    if (!ok) {
      final showMsg = msg.isNotEmpty ? msg : 'Request failed';
      if (ApiService.isPhoneNotVerified(res) ||
          ApiService.isPhoneNotVerified(showMsg)) {
        await showPhoneVerificationRequiredDialog(
          context,
          message: showMsg,
          onRetry: _withdrawAll,
        );
        return;
      }
      if (ApiService.isTierOrKycRestriction(res) ||
          ApiService.isTierOrKycRestriction(showMsg)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showMsg),
            action: SnackBarAction(
              label: 'Verify ID',
              onPressed: () {
                Navigator.push(
                  context,
                  FTPageRoute.slideUp(child: const KycScreen()),
                );
              },
            ),
          ),
        );
        return;
      }
      UIFeedback.showErrorSnack(context, showMsg);
      return;
    }

    UIFeedback.showSuccessSnack(context, 'Withdrawal moved to wallet');
    await AnalyticsHooks.instance.withdrawalInitiated(
      source: 'moneybox',
      amount: payout,
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoneyActionReceiptScreen(
          title: 'MoneyBox withdrawal',
          statusLabel: 'Completed',
          amount: payout,
          reference: (res['reference'] ?? res['request_id'] ?? '').toString(),
          destination: 'Wallet balance',
        ),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final principal = double.tryParse(
            widget.status['principal_balance']?.toString() ?? '0') ??
        0;
    final bonus =
        double.tryParse(widget.status['projected_bonus']?.toString() ?? '0') ??
            0;
    final penaltyRate = _penaltyRate();
    final penalty = principal * penaltyRate;
    final payout =
        (principal - penalty + bonus).clamp(0.0, double.infinity).toDouble();

    return FTScaffold(
      title: 'Withdraw',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Principal: ${formatNaira(principal)}'),
          Text('Projected bonus: ${formatNaira(bonus)}'),
          const SizedBox(height: 8),
          Text('Penalty rate: ${(penaltyRate * 100).toStringAsFixed(0)}%'),
          Text('Penalty estimate: ${formatNaira(penalty)}'),
          const SizedBox(height: 8),
          Text(
            'Estimated payout: ${formatNaira(payout)}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Early withdrawal voids your tier bonus.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          FTAsyncButton(
            label: 'Withdraw to Wallet',
            variant: FTButtonVariant.primary,
            externalLoading: _loading,
            onPressed: _loading ? null : _withdrawAll,
          ),
        ],
      ),
    );
  }
}

