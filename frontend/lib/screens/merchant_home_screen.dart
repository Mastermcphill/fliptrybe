import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/kpi_service.dart';
import '../services/leaderboard_service.dart';
import '../services/listing_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/auth_navigation.dart';
import '../widgets/email_verification_dialog.dart';
import '../widgets/how_it_works/role_how_it_works_entry_card.dart';
import 'create_listing_screen.dart';
import 'email_verify_screen.dart';
import 'growth/growth_analytics_screen.dart';
import 'leaderboards_screen.dart';
import 'moneybox_autosave_screen.dart';
import 'moneybox_tier_screen.dart';
import 'moneybox_withdraw_screen.dart';
import 'merchant_followers_screen.dart';
import 'support_chat_screen.dart';

class MerchantHomeScreen extends StatefulWidget {
  const MerchantHomeScreen({super.key, this.onSelectTab, this.autoLoad = true});

  final ValueChanged<int>? onSelectTab;
  final bool autoLoad;

  @override
  State<MerchantHomeScreen> createState() => _MerchantHomeScreenState();
}

class _MerchantHomeScreenState extends State<MerchantHomeScreen> {
  final _walletSvc = WalletService();
  final _moneyBoxSvc = MoneyBoxService();
  final _kpiSvc = KpiService();
  final _leaderSvc = LeaderboardService();
  final _listingSvc = ListingService();

  bool _loading = true;
  bool _signingOut = false;
  String? _error;

  Map<String, dynamic> _wallet = const {};
  Map<String, dynamic> _moneyBox = const {};
  Map<String, dynamic> _kpis = const {};
  Map<String, dynamic> _profile = const {};
  List<Map<String, dynamic>> _myListings = const [];
  int _rank = 0;
  String _merchantName = '';
  int _chartDays = 7;

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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await ApiService.getProfile();
      final meId = int.tryParse((me['id'] ?? '').toString()) ?? 0;
      final meName = (me['name'] ?? '').toString();
      final values = await Future.wait([
        _walletSvc.getWallet(),
        _moneyBoxSvc.status(),
        _kpiSvc.merchantKpis(),
        _leaderSvc.ranked(limit: 120),
        _listingSvc.listMyListings(),
      ]);
      if (!mounted) return;

      final ranked = (values[3] as List).whereType<Map>().toList();
      int rank = 0;
      for (final raw in ranked) {
        final row = Map<String, dynamic>.from(raw);
        final uid = int.tryParse((row['user_id'] ?? '').toString()) ?? 0;
        if (uid == meId && meId > 0) {
          rank = int.tryParse((row['rank'] ?? '').toString()) ?? 0;
          break;
        }
      }

      setState(() {
        _profile = Map<String, dynamic>.from(me);
        _wallet = (values[0] as Map<String, dynamic>?) ?? <String, dynamic>{};
        _moneyBox = values[1] as Map<String, dynamic>;
        _kpis = values[2] as Map<String, dynamic>;
        _myListings = (values[4] as List)
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        _rank = rank;
        _merchantName = meName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load merchant dashboard: $e';
      });
    }
  }

  Future<void> _safePush(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
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

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  String _money(dynamic value) => '₦${_num(value).toStringAsFixed(2)}';

  int _int(dynamic value) => int.tryParse((value ?? 0).toString()) ?? 0;

  Future<void> _openMoneyBoxGateAware(
    Future<Map<String, dynamic>> Function() call,
    VoidCallback onAllowed,
  ) async {
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

  List<FlSpot> _trendSpots() {
    final gross = _num(_kpis['gross_revenue']);
    final totalOrders = _int(_kpis['total_orders']);
    final base = gross > 0 ? gross : (totalOrders * 18000).toDouble();
    final perDay = base / max(_chartDays, 1);
    return List.generate(_chartDays, (index) {
      final wave = sin(index / 2.4) * (perDay * 0.18);
      final drift = (index / _chartDays) * (perDay * 0.12);
      final y = max(0, perDay + wave + drift).toDouble();
      return FlSpot(index.toDouble(), y);
    });
  }

  Widget _metricTile(String title, String value, {String? subtitle}) {
    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: FTCard(
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalOrders = _int(_kpis['total_orders']);
    final completedOrders = _int(_kpis['completed_orders']);
    final pendingOrders = _int(_kpis['pending_orders']) > 0
        ? _int(_kpis['pending_orders'])
        : max(totalOrders - completedOrders, 0);
    final grossRevenue = _money(_kpis['gross_revenue']);
    final platformFees = _money(_kpis['platform_fees']);

    final activeListings = _myListings.where((item) {
      final active = item['is_active'] == true ||
          item['is_active']?.toString().toLowerCase() == 'true' ||
          item['is_active']?.toString() == '1';
      final status = (item['status'] ?? '').toString().toLowerCase();
      return active && !status.contains('sold') && !status.contains('complete');
    }).length;
    final inactiveListings = _myListings.length - activeListings;
    final lowSignalListings = _myListings.where((item) {
      final views = _int(item['views']);
      return views > 0 && views < 3;
    }).length;

    final emailVerified = (_profile['email_verified'] == true) ||
        (_profile['email_verified_at'] ?? '').toString().trim().isNotEmpty;
    final kycStatus =
        (_profile['kyc_status'] ?? _profile['kyc'] ?? 'unknown').toString();
    final moneyboxLocked = _money(_moneyBox['principal_balance']);
    final moneyboxTier =
        _int(_moneyBox['tier']) > 0 ? _int(_moneyBox['tier']) : 1;
    final autosave = _int(_moneyBox['autosave_percent']);
    final daysRemaining = (_moneyBox['days_remaining'] ?? '-').toString();
    final bonusPct = (_moneyBox['bonus_percent'] ??
            _moneyBox['projected_bonus_percent'] ??
            '-')
        .toString();
    final spots = _trendSpots();

    return FTScaffold(
      title: _merchantName.trim().isEmpty
          ? 'Merchant Dashboard'
          : 'Merchant Dashboard • $_merchantName',
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        TextButton(
          onPressed: _signingOut ? null : _handleSignOut,
          child: Text(_signingOut ? 'Signing out...' : 'Sign out'),
        ),
      ],
      child: _loading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                FTSkeleton(height: 90),
                SizedBox(height: 10),
                FTSkeleton(height: 190),
                SizedBox(height: 10),
                FTSkeleton(height: 220),
              ],
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FTErrorState(message: _error!, onRetry: _reload),
                    ),
                  const FTSectionHeader(
                    title: 'Business Snapshot',
                    subtitle:
                        'Revenue, inventory health, and operations summary',
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.5,
                    children: [
                      _metricTile('Revenue (period)', grossRevenue),
                      _metricTile('Orders', '$totalOrders',
                          subtitle: '$completedOrders completed'),
                      _metricTile('Active Listings', '$activeListings',
                          subtitle: '$inactiveListings inactive'),
                      _metricTile(
                        _rank > 0 ? 'Leaderboard Rank' : 'Merchant Reach',
                        _rank > 0 ? '#$_rank' : 'Unranked',
                        subtitle: 'Balance: ${_money(_wallet['balance'])}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: FTSectionHeader(
                                title: 'Earnings Trend',
                                subtitle:
                                    'Lightweight projection for recent period',
                              ),
                            ),
                            SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 7, label: Text('7d')),
                                ButtonSegment(value: 14, label: Text('14d')),
                                ButtonSegment(value: 30, label: Text('30d')),
                              ],
                              selected: {_chartDays},
                              onSelectionChanged: (values) {
                                setState(() => _chartDays = values.first);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 180,
                          child: LineChart(
                            LineChartData(
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              titlesData: const FlTitlesData(show: false),
                              minX: 0,
                              maxX: (_chartDays - 1).toDouble(),
                              minY: 0,
                              lineBarsData: [
                                LineChartBarData(
                                  spots: spots,
                                  isCurved: true,
                                  barWidth: 3,
                                  color: const Color(0xFF0E7490),
                                  dotData: const FlDotData(show: false),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0x220E7490),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FTSectionHeader(
                          title: 'Inventory Health',
                          subtitle:
                              'Quick status of active, inactive, and pending order pressure',
                        ),
                        const SizedBox(height: 8),
                        Text('Active listings: $activeListings'),
                        Text('Inactive listings: $inactiveListings'),
                        Text('Pending orders: $pendingOrders'),
                        Text('Platform fees (period): $platformFees'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const FTSectionHeader(
                    title: 'Quick Actions',
                    subtitle: 'One-tap operational actions',
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.add_business_outlined,
                    label: 'Create Listing',
                    onTap: () => _safePush(const CreateListingScreen()),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.inventory_2_outlined,
                    label: 'Manage Listings',
                    onTap: () => widget.onSelectTab?.call(1),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.receipt_long_outlined,
                    label: 'View Orders',
                    onTap: () => widget.onSelectTab?.call(2),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.trending_up_outlined,
                    label: 'Growth Analytics',
                    onTap: () => widget.onSelectTab?.call(3),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.support_agent_outlined,
                    label: 'Support Chat (Admin)',
                    onTap: () {
                      if (widget.onSelectTab != null) {
                        widget.onSelectTab!(4);
                      } else {
                        _safePush(const SupportChatScreen());
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.people_alt_outlined,
                    label: 'Followers',
                    onTap: () => _safePush(const MerchantFollowersScreen()),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.emoji_events_outlined,
                    label: 'Leaderboards',
                    onTap: () => _safePush(const LeaderboardsScreen()),
                  ),
                  const SizedBox(height: 8),
                  _quickAction(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Withdraw',
                    onTap: () => _openMoneyBoxGateAware(
                      () => _moneyBoxSvc.status(),
                      () =>
                          _safePush(MoneyBoxWithdrawScreen(status: _moneyBox)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FTSectionHeader(
                          title: 'Trust & Compliance',
                          subtitle:
                              'Verification gates are enforced before sensitive actions',
                        ),
                        const SizedBox(height: 8),
                        Text(
                            'Email verification: ${emailVerified ? 'Verified' : 'Not verified'}'),
                        Text('KYC status: $kycStatus'),
                        if (!emailVerified) ...[
                          const SizedBox(height: 8),
                          FTPrimaryButton(
                            label: 'Verify Email',
                            icon: Icons.verified_outlined,
                            onPressed: () =>
                                _safePush(const EmailVerifyScreen()),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FTSectionHeader(
                          title: 'MoneyBox',
                          subtitle: 'Tier, lock, bonus and autosave controls',
                        ),
                        const SizedBox(height: 8),
                        Text('Tier: $moneyboxTier'),
                        Text('Locked: $moneyboxLocked'),
                        Text('Autosave: $autosave%'),
                        Text('Bonus: $bonusPct%'),
                        Text('Days remaining: $daysRemaining'),
                        const SizedBox(height: 8),
                        const Text(
                          'Early withdrawal penalties: first third 7%, second third 5%, final third 2%, maturity 0%.',
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FTSecondaryButton(
                              label: 'Open / Change Tier',
                              icon: Icons.workspace_premium_outlined,
                              onPressed: () => _openMoneyBoxGateAware(
                                () => _moneyBoxSvc.status(),
                                () => _safePush(const MoneyBoxTierScreen()),
                              ),
                            ),
                            FTSecondaryButton(
                              label: 'Set Autosave',
                              icon: Icons.tune_outlined,
                              onPressed: () => _openMoneyBoxGateAware(
                                () => _moneyBoxSvc.status(),
                                () => _safePush(const MoneyBoxAutosaveScreen()),
                              ),
                            ),
                            FTSecondaryButton(
                              label: 'Withdraw',
                              icon: Icons.outbond_outlined,
                              onPressed: () => _openMoneyBoxGateAware(
                                () => _moneyBoxSvc.status(),
                                () => _safePush(
                                    MoneyBoxWithdrawScreen(status: _moneyBox)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        FTSectionHeader(
                          title: 'How FlipTrybe Updates You',
                          subtitle: 'Messaging and notifications visibility',
                        ),
                        SizedBox(height: 8),
                        Text(
                            'In-app notifications for transaction milestones.'),
                        Text('SMS/WhatsApp for critical alerts when enabled.'),
                        Text(
                            'Use Admin chat for escalation and dispute handling.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const RoleHowItWorksEntryCard(role: 'merchant'),
                  const SizedBox(height: 8),
                  FTSecondaryButton(
                    label: 'Estimate Earnings',
                    icon: Icons.calculate_outlined,
                    onPressed: () => _safePush(
                        const GrowthAnalyticsScreen(role: 'merchant')),
                  ),
                ],
              ),
            ),
    );
  }
}
