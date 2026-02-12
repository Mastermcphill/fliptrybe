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
import 'not_available_yet_screen.dart';
import 'admin_global_search_screen.dart';
import 'admin_anomalies_screen.dart';
import 'admin_risk_events_screen.dart';
import '../utils/auth_navigation.dart';

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

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_guardError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Hub')),
        body: Center(child: Text(_guardError!)),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Hub'),
        actions: [
          TextButton(
            onPressed: _signingOut ? null : _handleSignOut,
            child: Text(
              _signingOut ? 'Signing out...' : 'Sign out',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Admin tools (demo-ready).',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Payout Console'),
            subtitle: const Text('Approve / reject / mark paid'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminPayoutConsoleScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Audit Logs'),
            subtitle: const Text('Everything the system is doing'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminAuditScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Support Chat'),
            subtitle: const Text('View and reply to support threads'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminSupportThreadsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Autopilot'),
            subtitle: const Text('Automate payouts, queue + driver assignment'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminAutopilotScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('Manual Payments'),
            subtitle: const Text('Review manual payment intents and mark paid'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminManualPaymentsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notify Queue'),
            subtitle:
                const Text('Retry and manage outbound notification queue'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminNotifyQueueScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Role Approvals'),
            subtitle: const Text('Approve merchants, drivers, inspectors'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminRoleApprovalsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.assignment_ind_outlined),
            title: const Text('Inspector Requests'),
            subtitle: const Text('Review inspector access requests'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminInspectorRequestsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('KYC Review'),
            subtitle: const Text('Approve or reject KYC submissions'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminKycReviewScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.manage_search_outlined),
            title: const Text('Global Search'),
            subtitle: const Text('Search users, orders, listings, intents'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminGlobalSearchScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Marketplace'),
            subtitle: const Text('Browse and search listings as admin'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminMarketplaceScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Leaderboards'),
            subtitle: const Text('Top merchants & drivers'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LeaderboardsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.rule_folder_outlined),
            title: const Text('Anomalies'),
            subtitle: const Text('Detect payment, escrow and webhook drifts'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminAnomaliesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Risk Events'),
            subtitle: const Text('Review throttles, spam and abuse signals'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdminRiskEventsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.percent_outlined),
            title: const Text('Commission Rules'),
            subtitle: const Text('Set commission by kind/state/category'),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminCommissionRulesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Dispute Resolution'),
            subtitle: const Text('Not available yet'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotAvailableYetScreen(
                  title: 'Dispute Resolution',
                  reason: 'Dispute workflows are not enabled in this release.',
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Inspector Bonds'),
            subtitle: const Text('Not available yet'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotAvailableYetScreen(
                  title: 'Inspector Bonds',
                  reason:
                      'Inspector bond workflows are not enabled in this release.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
