import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/wallet_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/ui_feedback.dart';
import '../widgets/email_verification_dialog.dart';

class MerchantWithdrawScreen extends StatefulWidget {
  const MerchantWithdrawScreen({super.key});

  @override
  State<MerchantWithdrawScreen> createState() => _MerchantWithdrawScreenState();
}

class _MerchantWithdrawScreenState extends State<MerchantWithdrawScreen> {
  final _svc = WalletService();

  final _amount = TextEditingController();
  final _bankName = TextEditingController(text: 'GTBank');
  final _acctNo = TextEditingController();
  final _acctName = TextEditingController();

  final _amountFocus = FocusNode();
  final _bankFocus = FocusNode();
  final _acctNoFocus = FocusNode();
  final _acctNameFocus = FocusNode();

  bool _loading = false;
  String? _amountError;
  String? _acctNoError;

  void _toast(String msg) {
    if (!mounted) return;
    UIFeedback.showErrorSnack(context, msg);
  }

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
    if (!_validate()) return;

    final amt = double.parse(_amount.text.trim());
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
    final msg = (res['message'] ??
            res['error'] ??
            (ok ? 'Payout request sent' : 'Failed'))
        .toString();
    if (!ok &&
        (ApiService.isEmailNotVerified(res) ||
            ApiService.isEmailNotVerified(msg))) {
      await showEmailVerificationRequiredDialog(
        context,
        message: msg,
        onRetry: _submit,
      );
      return;
    }
    if (!mounted) return;
    if (ok) {
      UIFeedback.showSuccessSnack(context, msg);
      Navigator.pop(context);
      return;
    }
    _toast(msg);
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
            labelText: 'Amount (₦)',
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
          const SizedBox(height: 14),
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
