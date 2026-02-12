import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/kpi_service.dart';
import '../services/leaderboard_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import 'create_listing_screen.dart';
import 'email_verify_screen.dart';
import 'moneybox_autosave_screen.dart';
import 'moneybox_tier_screen.dart';
import 'moneybox_withdraw_screen.dart';
import 'leaderboards_screen.dart';
import 'support_chat_screen.dart';
import '../widgets/email_verification_dialog.dart';
import 'not_available_yet_screen.dart';
import 'growth/growth_analytics_screen.dart';
import '../widgets/how_it_works/role_how_it_works_entry_card.dart';
import '../utils/auth_navigation.dart';

class MerchantHomeScreen extends StatefulWidget {
  final ValueChanged<int>? onSelectTab;
  final bool autoLoad;
  const MerchantHomeScreen({super.key, this.onSelectTab, this.autoLoad = true});

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  final _walletSvc = WalletService();
  final _moneyBoxSvc = MoneyBoxService();
  final _kpiSvc = KpiService();
  final _leaderSvc = LeaderboardService();
  bool _loading = true;
  bool _signingOut = false;
  Map<String, dynamic> _wallet = const {};
  Map<String, dynamic> _moneyBox = const {};
  Map<String, dynamic> _kpis = const {};
  Map<String, dynamic> _profile = const {};
  int _rank = 0;
  String _merchantName = '';

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _reload();
    } else {
      _loading = false;
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final me = await ApiService.getProfile();
      final meId = int.tryParse((me['id'] ?? '').toString()) ?? 0;
      final meName = (me['name'] ?? '').toString();
      final results = await Future.wait([
        _walletSvc.getWallet(),
        _moneyBoxSvc.status(),
        _kpiSvc.merchantKpis(),
        _leaderSvc.ranked(limit: 100),
      ]);

      final wallet =
          (results[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final moneyBox = results[1] as Map<String, dynamic>;
      final kpis = results[2] as Map<String, dynamic>;
      final ranked = (results[3] as List).whereType<Map>().toList();
      int rank = 0;
      for (final raw in ranked) {
        final m = Map<String, dynamic>.from(raw);
        final uid = int.tryParse((m['user_id'] ?? '').toString()) ?? 0;
        if (uid == meId && meId > 0) {
          rank = int.tryParse((m['rank'] ?? '').toString()) ?? 0;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = Map<String, dynamic>.from(me);
        _wallet = wallet;
        _moneyBox = moneyBox;
        _kpis = kpis;
        _rank = rank;
        _merchantName = meName;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _money(dynamic v) {
    final n = double.tryParse((v ?? 0).toString()) ?? 0;
    return n.toStringAsFixed(2);
  }

  Future<void> _safePush(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _reload();
  }

  Future<void> _createListing() async {
    await _safePush(const CreateListingScreen());
  }

  Future<void> _handleSignOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await logoutToLanding(context);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _openMoneyBoxGateAware(
      Future<Map<String, dynamic>> Function() call,
      VoidCallback onAllowed) async {
    final res = await call();
    if (!mounted) return;
    if (ApiService.isEmailNotVerified(res)) {
      await showEmailVerificationRequiredDialog(
        context,
        message: (res['message'] ?? 'Verify your email to continue').toString(),
      );
      return;
    }
    onAllowed();
  }

  Widget _snapCard(String title, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingOrders =
        int.tryParse((_kpis['pending_orders'] ?? 0).toString()) ??
            ((int.tryParse((_kpis['total_orders'] ?? 0).toString()) ?? 0) -
                (int.tryParse((_kpis['completed_orders'] ?? 0).toString()) ??
                    0));
    final moneyboxLocked = _moneyBox['principal_balance'] ?? 0;
    final tier = int.tryParse((_moneyBox['tier'] ?? 1).toString()) ?? 1;
    final autosave =
        int.tryParse((_moneyBox['autosave_percent'] ?? 0).toString()) ?? 0;
    final daysRemaining = (_moneyBox['days_remaining'] ?? '-').toString();
    final bonusPct = (_moneyBox['bonus_percent'] ??
            _moneyBox['projected_bonus_percent'] ??
            '-')
        .toString();
    final emailVerified = (_profile['email_verified'] == true) ||
        (_profile['email_verified_at'] ?? '').toString().trim().isNotEmpty;
    final kycRaw = (_profile['kyc_status'] ?? _profile['kyc'] ?? '').toString();
    final kycStatus = kycRaw.trim().isEmpty ? 'unknown' : kycRaw;

    return Scaffold(
      appBar: AppBar(
        title: Text(_merchantName.trim().isEmpty
            ? 'Merchant Home'
            : 'Merchant Home - $_merchantName'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          TextButton(
            onPressed: _signingOut ? null : _handleSignOut,
            child: Text(_signingOut ? 'Signing out...' : 'Sign out'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('Business Snapshot',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _snapCard('Available Balance',
                          '?${_money(_wallet['balance'])}'),
                      const SizedBox(width: 8),
                      _snapCard('Escrow Pending', '$pendingOrders orders'),
                    ],
                  ),
                  Row(
                    children: [
                      _snapCard(
                          'MoneyBox Locked', '?${_money(moneyboxLocked)}'),
                      const SizedBox(width: 8),
                      _snapCard('Leaderboard Rank',
                          _rank > 0 ? '#$_rank' : 'Unranked'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Primary Actions',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  _actionButton(
                      icon: Icons.add_business_outlined,
                      label: 'Create Listing',
                      onTap: _createListing),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.inventory_2_outlined,
                    label: 'My Listings',
                    onTap: () => widget.onSelectTab?.call(1),
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'View Orders',
                    onTap: () => widget.onSelectTab?.call(2),
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.support_agent_outlined,
                    label: 'Chat Admin',
                    onTap: () {
                      if (widget.onSelectTab != null) {
                        widget.onSelectTab!(4);
                      } else {
                        _safePush(const SupportChatScreen());
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.people_alt_outlined,
                    label: 'Followers',
                    onTap: () => _safePush(
                      const NotAvailableYetScreen(
                        title: 'Followers',
                        reason:
                            'Followers detail is not enabled yet. Use Merchant Growth and Leaderboards meanwhile.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.emoji_events_outlined,
                    label: 'Leaderboards',
                    onTap: () => _safePush(const LeaderboardsScreen()),
                  ),
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.calculate_outlined,
                    label: 'Estimate Earnings',
                    onTap: () {
                      if (widget.onSelectTab != null) {
                        widget.onSelectTab!(3);
                      } else {
                        _safePush(
                            const GrowthAnalyticsScreen(role: 'merchant'));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const RoleHowItWorksEntryCard(role: 'merchant'),
                  const SizedBox(height: 16),
                  const Text('KPI Quick Stats',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      'Total Orders: ${_kpis['total_orders'] ?? 0}')),
                              Expanded(
                                  child: Text(
                                      'Completed: ${_kpis['completed_orders'] ?? 0}')),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                  child: Text(
                                      'Gross Revenue: ?${_kpis['gross_revenue'] ?? 0}')),
                              Expanded(
                                  child: Text(
                                      'Platform Fees: ?${_kpis['platform_fees'] ?? 0}')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Trust & Compliance',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Email verification: ${emailVerified ? 'Verified' : 'Not verified'}'),
                          Text('KYC status: $kycStatus'),
                          const SizedBox(height: 8),
                          const Text(
                            'Listing creation, withdrawals, and tier upgrades require verified email.',
                          ),
                          if (!emailVerified) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () =>
                                  _safePush(const EmailVerifyScreen()),
                              child: const Text('Verify Email'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('MoneyBox Panel',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tier: $tier'),
                          Text('Autosave: $autosave%'),
                          Text('Bonus %: $bonusPct'),
                          Text('Days Remaining: $daysRemaining'),
                          const SizedBox(height: 10),
                          const Text(
                              'Penalty preview: first third 7%, second third 5%, final third 2%, maturity 0%'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _openMoneyBoxGateAware(
                                  () => _moneyBoxSvc.status(),
                                  () => _safePush(const MoneyBoxTierScreen()),
                                ),
                                child: const Text('Open / Change Tier'),
                              ),
                              OutlinedButton(
                                onPressed: () => _openMoneyBoxGateAware(
                                  () => _moneyBoxSvc.status(),
                                  () =>
                                      _safePush(const MoneyBoxAutosaveScreen()),
                                ),
                                child: const Text('Set Autosave'),
                              ),
                              OutlinedButton(
                                onPressed: () => _openMoneyBoxGateAware(
                                  () => _moneyBoxSvc.status(),
                                  () => _safePush(MoneyBoxWithdrawScreen(
                                      status: _moneyBox)),
                                ),
                                child: const Text('Withdraw'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('How FlipTrybe Updates You',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'In-app notifications track timeline changes. SMS/WhatsApp dispatches critical events when integrations are enabled. Use Admin chat for dispute escalation.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  if ((_moneyBox['status'] ?? '')
                      .toString()
                      .toLowerCase()
                      .contains('not_eligible'))
                    ListTile(
                      leading: const Icon(Icons.verified_outlined),
                      title: const Text(
                          'Verify email to unlock sensitive actions'),
                      subtitle: const Text(
                          'Listing creation, withdrawals, and tier upgrades require verification.'),
                      trailing: TextButton(
                        onPressed: () => _safePush(const EmailVerifyScreen()),
                        child: const Text('Verify now'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
