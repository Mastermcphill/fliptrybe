import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import 'merchant_withdraw_screen.dart';
import 'topup_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletService _svc = WalletService();

  bool _loading = true;
  Map<String, dynamic>? _wallet;
  List<dynamic> _ledger = const <dynamic>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() => super.dispose();

  Future<void> _load() async {
    setState(() => _loading = true);
    final wallet = await _svc.getWallet();
    final ledger = await _svc.ledger();
    if (!mounted) return;
    setState(() {
      _wallet = wallet;
      _ledger = ledger;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final balance = double.tryParse('${_wallet?['balance'] ?? 0}') ?? 0;

    return FTScaffold(
      title: 'Wallet',
      onRefresh: _load,
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: null,
        onRetry: _load,
        empty: false,
        loadingState: FTSkeletonList(
          itemCount: 4,
          itemBuilder: (_, __) => const FTSkeletonCard(height: 94),
        ),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          children: [
            FTSection(
              title: 'Available balance',
              subtitle: 'Use this wallet for orders and withdrawals.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatNaira(balance),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  FTPrimaryCtaRow(
                    primaryLabel: 'Top up wallet',
                    onPrimary: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TopupScreen()),
                      );
                      if (!mounted) return;
                      _load();
                    },
                    secondaryLabel: 'Withdraw',
                    onSecondary: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MerchantWithdrawScreen(),
                        ),
                      );
                      if (!mounted) return;
                      _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FTSection(
              title: 'Ledger',
              subtitle: 'Recent wallet movements and references.',
              child: _ledger.isEmpty
                  ? FTEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No transactions yet',
                      subtitle:
                          'Wallet entries will appear after your first activity.',
                      primaryCtaText: 'Refresh',
                      onPrimaryCta: _load,
                    )
                  : Column(
                      children: _ledger
                          .whereType<Map>()
                          .map((raw) => Map<String, dynamic>.from(raw))
                          .map((row) {
                        final direction = (row['direction'] ?? '').toString();
                        final amount =
                            double.tryParse('${row['amount'] ?? 0}') ?? 0;
                        final kind = (row['kind'] ?? '').toString();
                        final note = (row['note'] ?? '').toString();
                        return FTListTile(
                          leading: Icon(
                            direction.toLowerCase() == 'credit'
                                ? Icons.arrow_downward_outlined
                                : Icons.arrow_upward_outlined,
                          ),
                          title: '$direction ${formatNaira(amount)}',
                          subtitle:
                              '$kind${note.trim().isEmpty ? '' : ' - $note'}',
                          onTap: null,
                        );
                      }).toList(growable: false),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
