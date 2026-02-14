import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/analytics_hooks.dart';
import '../services/topup_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';
import 'money_action_receipt_screen.dart';

class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final TopupService _svc = TopupService();
  final TextEditingController _amount = TextEditingController(text: '1000');

  bool _loading = false;
  String _reference = '';
  String _url = '';
  bool _waiting = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (_loading) return;
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      UIFeedback.showErrorSnack(context, 'Enter a valid amount.');
      return;
    }

    final confirmed = await showMoneyConfirmationSheet(
      context,
      FTMoneyConfirmationPayload(
        title: 'Confirm wallet top-up',
        amount: amount,
        fee: 0,
        total: amount,
        destination: 'Wallet balance',
        actionLabel: 'Initialize payment',
      ),
    );
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    try {
      final res = await _svc.initialize(amount);
      if (!mounted) return;
      final reference = (res['reference'] ?? '').toString();
      final url = (res['authorization_url'] ?? '').toString();
      setState(() {
        _reference = reference;
        _url = url;
        _waiting = url.isNotEmpty;
      });
      await AnalyticsHooks.instance.track(
        'payment_initialized',
        properties: <String, Object?>{
          'channel': 'paystack',
          'amount': amount,
          'reference': reference,
        },
      );
      UIFeedback.showSuccessSnack(context, 'Payment initialized.');
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, 'Initialization failed: $e');
      await AnalyticsHooks.instance.paymentFail(
        channel: 'paystack',
        reason: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPaystackPage() async {
    final uri = Uri.tryParse(_url);
    if (uri == null) {
      UIFeedback.showErrorSnack(context, 'Invalid payment URL.');
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    setState(() => _waiting = true);
    await AnalyticsHooks.instance.track(
      'payment_browser_open',
      properties: <String, Object?>{'reference': _reference},
    );
  }

  Future<void> _showReceipt() async {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MoneyActionReceiptScreen(
          title: 'Top-up receipt',
          statusLabel: _waiting ? 'Processing' : 'Initialized',
          amount: amount,
          reference: _reference,
          destination: 'Wallet balance',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(_amount.text.trim()) ?? 0;

    return FTScaffold(
      title: 'Top up Wallet',
      child: ListView(
        children: [
          FTSection(
            title: 'Add funds',
            subtitle: 'Your wallet is credited after provider confirmation.',
            child: Column(
              children: [
                FTTextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  labelText: 'Amount (NGN)',
                  prefixIcon: Icons.payments_outlined,
                  enabled: !_loading,
                ),
                const SizedBox(height: 10),
                FTAsyncButton(
                  label: 'Initialize payment',
                  icon: Icons.account_balance_wallet_outlined,
                  externalLoading: _loading,
                  onPressed: _loading ? null : _init,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FTSection(
            title: 'Payment status',
            subtitle: 'Reference and next actions for this top-up.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount: ${formatNaira(amount)}'),
                Text('Reference: ${_reference.isEmpty ? '-' : _reference}'),
                if (_url.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  FTButton(
                    label: 'Open payment page',
                    variant: FTButtonVariant.secondary,
                    icon: Icons.open_in_new,
                    expand: true,
                    onPressed: _openPaystackPage,
                  ),
                ],
                if (_waiting) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Processing payment confirmation. Use refresh from wallet to verify balance updates.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (_reference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FTButton(
                    label: 'View receipt',
                    variant: FTButtonVariant.ghost,
                    expand: true,
                    onPressed: _showReceipt,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
