import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/analytics_hooks.dart';
import '../services/wallet_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/role_gates.dart';
import '../utils/ui_feedback.dart';
import '../widgets/phone_verification_dialog.dart';
import 'money_action_receipt_screen.dart';

class MerchantWithdrawScreen extends StatefulWidget {
  const MerchantWithdrawScreen({super.key});

  @override
  State<MerchantWithdrawScreen> createState() => _MerchantWithdrawScreenState();
}

class _MerchantWithdrawScreenState extends State<MerchantWithdrawScreen> {
  final WalletService _svc = WalletService();

  final TextEditingController _amount = TextEditingController();
  final TextEditingController _bankName = TextEditingController(text: 'GTBank');
  final TextEditingController _acctNo = TextEditingController();
  final TextEditingController _acctName = TextEditingController();

  final FocusNode _amountFocus = FocusNode();
  final FocusNode _bankFocus = FocusNode();
  final FocusNode _acctNoFocus = FocusNode();
  final FocusNode _acctNameFocus = FocusNode();

  bool _loading = false;
  String? _amountError;
  String? _acctNoError;

  bool _validate() {
    final amt = double.tryParse(_amount.text.trim()) ?? 0.0;
    final acctNo = _acctNo.text.trim();
    setState(() {
      _amountError = amt <= 0 ? 'Enter a valid amount' : null;
      _acctNoError = acctNo.length < 8 ? 'Enter valid account number' : null;
    });
    return _amountError == null && _acctNoError == null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final profile = await ApiService.getProfile();
    final gate = RoleGates.forWithdraw(profile);
    final gateAllowed = await guardRestrictedAction(
      context,
      block: gate,
      authAction: 'withdraw earnings',
      onAllowed: () async {},
    );
    if (!gateAllowed) return;

    if (!_validate()) return;

    final amount = double.parse(_amount.text.trim());
    final confirmed = await showMoneyConfirmationSheet(
      context,
      FTMoneyConfirmationPayload(
        title: 'Confirm withdrawal',
        amount: amount,
        fee: 0,
        total: amount,
        destination: '${_bankName.text.trim()} - ${_acctNo.text.trim()}',
        actionLabel: 'Submit request',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    final res = await _svc.requestPayout(
      amount: amount,
      bankName: _bankName.text.trim(),
      accountNumber: _acctNo.text.trim(),
      accountName: _acctName.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);

    final ok = res['ok'] == true;
    final message = (res['message'] ??
            res['error'] ??
            (ok ? 'Payout request sent' : 'Failed'))
        .toString();

    if (!ok &&
        (ApiService.isPhoneNotVerified(res) ||
            ApiService.isPhoneNotVerified(message))) {
      await showPhoneVerificationRequiredDialog(
        context,
        message: message,
        onRetry: _submit,
      );
      return;
    }

    if (!mounted) return;
    if (ok) {
      await AnalyticsHooks.instance.withdrawalInitiated(
        source: 'wallet',
        amount: amount,
      );
      UIFeedback.showSuccessSnack(context, message);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MoneyActionReceiptScreen(
            title: 'Withdrawal receipt',
            statusLabel: 'Pending review',
            amount: amount,
            reference: (res['reference'] ?? res['request_id'] ?? '').toString(),
            destination: '${_bankName.text.trim()} - ${_acctNo.text.trim()}',
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }

    UIFeedback.showErrorSnack(context, message);
  }

  @override
  void dispose() {
    _amount.dispose();
    _bankName.dispose();
    _acctNo.dispose();
    _acctName.dispose();
    _amountFocus.dispose();
    _bankFocus.dispose();
    _acctNoFocus.dispose();
    _acctNameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;

    return FTScaffold(
      title: 'Withdraw / Payout Request',
      child: ListView(
        children: [
          Text(
            'Request a withdrawal to your bank account.',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FTTextField(
            controller: _amount,
            focusNode: _amountFocus,
            nextFocusNode: _bankFocus,
            keyboardType: TextInputType.number,
            labelText: 'Amount (NGN)',
            prefixIcon: Icons.payments_outlined,
            errorText: _amountError,
            enabled: !_loading,
            onChanged: (_) {
              if (_amountError != null) {
                setState(() => _amountError = null);
              }
            },
          ),
          const SizedBox(height: 10),
          FTTextField(
            controller: _bankName,
            focusNode: _bankFocus,
            nextFocusNode: _acctNoFocus,
            labelText: 'Bank Name',
            prefixIcon: Icons.account_balance_outlined,
            enabled: !_loading,
          ),
          const SizedBox(height: 10),
          FTTextField(
            controller: _acctNo,
            focusNode: _acctNoFocus,
            nextFocusNode: _acctNameFocus,
            keyboardType: TextInputType.number,
            labelText: 'Account Number',
            prefixIcon: Icons.pin_outlined,
            errorText: _acctNoError,
            enabled: !_loading,
            onChanged: (_) {
              if (_acctNoError != null) {
                setState(() => _acctNoError = null);
              }
            },
          ),
          const SizedBox(height: 10),
          FTTextField(
            controller: _acctName,
            focusNode: _acctNameFocus,
            textInputAction: TextInputAction.done,
            labelText: 'Account Name (optional)',
            prefixIcon: Icons.person_outline,
            enabled: !_loading,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            'Amount to send: ${formatNaira(amount)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          FTAsyncButton(
            label: 'Submit Request',
            icon: Icons.send,
            variant: FTButtonVariant.primary,
            externalLoading: _loading,
            onPressed: _loading ? null : _submit,
          ),
        ],
      ),
    );
  }
}
