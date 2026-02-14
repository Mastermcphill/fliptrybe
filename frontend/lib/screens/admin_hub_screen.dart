import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'admin_payout_console_screen.dart';
import 'admin_commission_rules_screen.dart';
import 'admin_notify_queue_screen.dart';
import 'admin_autopilot_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_kyc_review_screen.dart';
import 'admin_role_approvals_screen.dart';
import 'admin_inspector_requests_screen.dart';
import 'admin_manual_payments_screen.dart';
import 'admin_marketplace_screen.dart';
import 'leaderboards_screen.dart';
import 'admin_support_threads_screen.dart';
import 'notifications_inbox_screen.dart';
import 'not_available_yet_screen.dart';
import 'admin_global_search_screen.dart';
import 'admin_anomalies_screen.dart';
import 'admin_risk_events_screen.dart';
import 'admin_system_health_screen.dart';
import 'admin_feature_flags_screen.dart';
import 'admin_growth_analytics_screen.dart';
import 'investor_metrics_screen.dart';
import 'admin_commission_engine_screen.dart';
import 'admin_liquidity_lab_screen.dart';
import '../utils/auth_navigation.dart';
import '../utils/ft_routes.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';

class AdminHubScreen extends StatefulWidget {
  const AdminHubScreen({super.key});

  @override
  State<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends State<AdminHubScreen> {
  bool _signingOut = false;
  bool _checking = true;
  String? _guardError;
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    _ensureAdmin();
  }

  Future<void> _ensureAdmin() async {
    try {
      final me = await _auth.me();
      final role = (me?['role'] ?? '').toString().toLowerCase();
      if (!mounted) return;
      if (role != 'admin') {
        setState(() {
          _guardError = 'Admin access required.';
          _checking = false;
        });
        return;
      }
      setState(() => _checking = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardError = 'Unable to verify admin access.';
        _checking = false;
      });
    }
  }

  Future<bool> _confirmSignOut() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleSignOut() async {
    if (_signingOut) return;
    final confirmed = await _confirmSignOut();
    if (!confirmed || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await logoutToLanding(context);
    } finally {
      if (mounted) {
        setState(() => _signingOut = false);
      }
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      FTRoutes.page(child: screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return AdminScaffold(
        title: 'Admin Hub',
        child: FTSkeletonList(
          itemCount: 8,
          itemBuilder: (context, _) => const FTSkeletonCard(height: 76),
        ),
      );
    }
    if (_guardError != null) {
      return AdminScaffold(
        title: 'Admin Hub',
        child: FTEmptyState(
          icon: Icons.admin_panel_settings_outlined,
          title: 'Admin access required',
          subtitle: _guardError!,
          primaryCtaText: 'Retry',
          onPrimaryCta: _ensureAdmin,
          secondaryCtaText: 'Go to Settings',
          onSecondaryCta: () => _open(const AdminAutopilotScreen()),
        ),
      );
    }
    return AdminScaffold(
      title: 'Admin Hub',
      actions: [
        Semantics(
          label: 'Sign out',
          button: true,
          child: TextButton(
            onPressed: _signingOut ? null : _handleSignOut,
            child: Text(
              _signingOut ? 'Signing out...' : 'Sign out',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
      body: ListView(
        cacheExtent: 720,
        children: [
          const Text(
            'Admin tools (demo-ready).',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          FTTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Payout Console'),
            subtitle: const Text('Approve / reject / mark paid'),
            onTap: () => _open(const AdminPayoutConsoleScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Audit Logs'),
            subtitle: const Text('Everything the system is doing'),
            onTap: () => _open(const AdminAuditScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Support Chat'),
            subtitle: const Text('View and reply to support threads'),
            onTap: () => _open(const AdminSupportThreadsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notification Center'),
            subtitle: const Text('Read outbound alerts and internal notices'),
            onTap: () => _open(const NotificationsInboxScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Autopilot'),
            subtitle: const Text('Automate payouts, queue + driver assignment'),
            onTap: () => _open(const AdminAutopilotScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Manual Payments'),
            subtitle: const Text('Review manual payment intents and mark paid'),
            onTap: () => _open(const AdminManualPaymentsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notify Queue'),
            subtitle:
                const Text('Retry and manage outbound notification queue'),
            onTap: () => _open(const AdminNotifyQueueScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Role Approvals'),
            subtitle: const Text('Approve merchants, drivers, inspectors'),
            onTap: () => _open(const AdminRoleApprovalsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.assignment_ind_outlined),
            title: const Text('Inspector Requests'),
            subtitle: const Text('Review inspector access requests'),
            onTap: () => _open(const AdminInspectorRequestsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('KYC Review'),
            subtitle: const Text('Approve or reject KYC submissions'),
            onTap: () => _open(const AdminKycReviewScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('System Health'),
            subtitle:
                const Text('Queue backlog, runner state, payout pressure'),
            onTap: () => _open(const AdminSystemHealthScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Growth Analytics'),
            subtitle:
                const Text('GMV, commissions, growth trend and projections'),
            onTap: () => _open(const AdminGrowthAnalyticsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Commission Engine'),
            subtitle: const Text('Versioned commission policies and preview'),
            onTap: () => _open(const AdminCommissionEngineScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.waterfall_chart_outlined),
            title: const Text('Liquidity Lab'),
            subtitle: const Text('Stress test platform liquidity and runway'),
            onTap: () => _open(const AdminLiquidityLabScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.stacked_line_chart_outlined),
            title: const Text('Investor Dashboard'),
            subtitle: const Text(
                'Unit economics and CSV export for investor reporting'),
            onTap: () => _open(const InvestorMetricsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.manage_search_outlined),
            title: const Text('Global Search'),
            subtitle: const Text('Search users, orders, listings, intents'),
            onTap: () => _open(const AdminGlobalSearchScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Marketplace'),
            subtitle: const Text('Browse and search listings as admin'),
            onTap: () => _open(const AdminMarketplaceScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Leaderboards'),
            subtitle: const Text('Top merchants & drivers'),
            onTap: () => _open(const LeaderboardsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.rule_folder_outlined),
            title: const Text('Anomalies'),
            subtitle: const Text('Detect payment, escrow and webhook drifts'),
            onTap: () => _open(const AdminAnomaliesScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Risk Events'),
            subtitle: const Text('Review throttles, spam and abuse signals'),
            onTap: () => _open(const AdminRiskEventsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.toggle_on_outlined),
            title: const Text('Feature Flags'),
            subtitle: const Text('Runtime toggles for payments, jobs, media'),
            onTap: () => _open(const AdminFeatureFlagsScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.percent_outlined),
            title: const Text('Commission Rules'),
            subtitle: const Text('Set commission by kind/state/category'),
            onTap: () => _open(const AdminCommissionRulesScreen()),
          ),
          FTTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Dispute Resolution'),
            subtitle: const Text('Not available yet'),
            onTap: () => _open(
              const NotAvailableYetScreen(
                title: 'Dispute Resolution',
                reason: 'Dispute workflows are not enabled in this release.',
              ),
            ),
          ),
          FTTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Inspector Bonds'),
            subtitle: const Text('Not available yet'),
            onTap: () => _open(
              const NotAvailableYetScreen(
                title: 'Inspector Bonds',
                reason:
                    'Inspector bond workflows are not enabled in this release.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
