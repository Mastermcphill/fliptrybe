import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';
import '../services/admin_notify_queue_service.dart';
import '../services/admin_role_service.dart';
import '../services/admin_wallet_service.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/kyc_service.dart';
import '../services/leaderboard_service.dart';
import '../ui/components/app_components.dart';
import '../ui/components/ft_components.dart';
import 'not_available_yet_screen.dart';

class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  final _autopilot = AdminAutopilotService();
  final _notify = AdminNotifyQueueService();
  final _roles = AdminRoleService();
  final _wallet = AdminWalletService();
  final _kyc = KycService();
  final _leaderboards = LeaderboardService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _autopilotStatus = const {};
  List<dynamic> _queueItems = const [];
  List<dynamic> _pendingRoles = const [];
  List<dynamic> _pendingInspectors = const [];
  List<dynamic> _pendingKyc = const [];
  List<dynamic> _pendingPayouts = const [];
  List<dynamic> _topLeaders = const [];

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _reload();
    } else {
      _loading = false;
    }
  }

  Future<List<dynamic>> _fetchInspectorPending() async {
    try {
      final res = await ApiClient.instance.dio.get(
        ApiConfig.api('/admin/inspector-requests?status=pending'),
      );
      final data = res.data;
      if (data is Map && data['items'] is List) {
        return data['items'] as List;
      }
      return <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _autopilot.status(),
        _notify.list(),
        _roles.pending(status: 'PENDING', limit: 100),
        _fetchInspectorPending(),
        _kyc.adminPending(),
        _wallet.listPayouts(status: 'pending'),
        _leaderboards.ranked(limit: 5),
      ]);
      if (!mounted) return;
      setState(() {
        _autopilotStatus = values[0] as Map<String, dynamic>;
        _queueItems = values[1] as List<dynamic>;
        _pendingRoles = values[2] as List<dynamic>;
        _pendingInspectors = values[3] as List<dynamic>;
        _pendingKyc = values[4] as List<dynamic>;
        _pendingPayouts = values[5] as List<dynamic>;
        _topLeaders = values[6] as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load admin overview.';
        _loading = false;
      });
    }
  }

  int _queueCountByStatus(String status) {
    return _queueItems.whereType<Map>().where((raw) {
      final mapped = Map<String, dynamic>.from(raw);
      return (mapped['status'] ?? '').toString().toLowerCase() ==
          status.toLowerCase();
    }).length;
  }

  Future<void> _seed(String path, String label) async {
    try {
      final res = await ApiClient.instance.postJson(ApiConfig.api(path), {});
      if (!mounted) return;
      final ok =
          (res is Map && (res['ok'] == true || (res['created'] != null)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(ok ? '$label completed.' : '$label response received.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().toLowerCase();
      if (text.contains('404')) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NotAvailableYetScreen(
              title: label,
              reason: '$label is not available on this backend deployment.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label failed: $e')),
      );
    }
  }

  Future<void> _toggleAutopilot() async {
    final enabled = _autopilotStatus['enabled'] == true;
    try {
      final res = await _autopilot.toggle(enabled: !enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text((res['message'] ?? 'Autopilot updated').toString())),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toggle failed: $e')),
      );
    }
  }

  Widget _metricTile(String label, int value) {
    return Expanded(
      child: FTMetricTile(
        label: label,
        value: '$value',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final integrations = (_autopilotStatus['integrations'] is Map)
        ? Map<String, dynamic>.from(_autopilotStatus['integrations'] as Map)
        : <String, dynamic>{};
    final health = (_autopilotStatus['integration_health'] is Map)
        ? Map<String, dynamic>.from(
            _autopilotStatus['integration_health'] as Map)
        : <String, dynamic>{};
    final mode = (integrations['mode'] ??
            _autopilotStatus['integrations_mode'] ??
            'unknown')
        .toString();
    final missing = (health['missing_env'] is List)
        ? (health['missing_env'] as List).map((e) => '$e').toList()
        : <String>[];
    final payProvider = (integrations['payments_provider'] ??
            _autopilotStatus['payments_provider'] ??
            'unknown')
        .toString();
    final paystackEnabled = integrations['paystack_enabled'] ??
        _autopilotStatus['paystack_enabled'] ??
        false;
    final smsEnabled = integrations['termii_enabled_sms'] ??
        _autopilotStatus['termii_enabled_sms'] ??
        false;
    final waEnabled = integrations['termii_enabled_wa'] ??
        _autopilotStatus['termii_enabled_wa'] ??
        false;
    final queueQueued = _queueCountByStatus('queued');
    final queueDead = _queueCountByStatus('dead');

    return FTScaffold(
      title: 'Admin Overview',
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _reload,
        empty: false,
        loadingState: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            FTMetricSkeletonTile(),
            SizedBox(height: 10),
            FTMetricSkeletonTile(),
            SizedBox(height: 10),
            FTListCardSkeleton(withImage: false),
          ],
        ),
        emptyState: const SizedBox.shrink(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FTSectionContainer(
              title: 'System Health',
              subtitle: 'Integration mode, provider, and configuration status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mode: $mode'),
                  Text('Payments provider: $payProvider'),
                  Text('Paystack enabled: $paystackEnabled'),
                  Text('Termii SMS enabled: $smsEnabled'),
                  Text('Termii WhatsApp enabled: $waEnabled'),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Missing keys: ${missing.join(', ')}'),
                  ],
                ],
              ),
            ),
            if (mode.toLowerCase() == 'live' && missing.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Text(
                  'Live mode is active with missing integration keys. Fix env configuration before processing payments/notifications.',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 16),
            const AppSectionHeader(
              title: 'Operational Counters',
              subtitle: 'Queue health and pending admin approvals',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _metricTile('Queue (queued)', queueQueued),
                const SizedBox(width: 8),
                _metricTile('Queue (dead)', queueDead),
              ],
            ),
            Row(
              children: [
                _metricTile('Pending Roles', _pendingRoles.length),
                const SizedBox(width: 8),
                _metricTile('Inspector Requests', _pendingInspectors.length),
              ],
            ),
            Row(
              children: [
                _metricTile('Pending KYC', _pendingKyc.length),
                const SizedBox(width: 8),
                _metricTile('Pending Payouts', _pendingPayouts.length),
              ],
            ),
            const SizedBox(height: 16),
            FTSectionContainer(
              title: 'Leaderboard Snapshot',
              subtitle: 'Top ranked merchants by current scoring logic',
              child: _topLeaders.isEmpty
                  ? const Text('No leaderboard data available.')
                  : Column(
                      children: _topLeaders.take(5).whereType<Map>().map((raw) {
                        final row = Map<String, dynamic>.from(raw);
                        final name =
                            (row['shop_name'] ?? row['name'] ?? 'Merchant')
                                .toString();
                        final score = (row['score'] ?? 0).toString();
                        final state = (row['state'] ?? '-').toString();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(name),
                          subtitle: Text('State: $state'),
                          trailing: Text('Score $score'),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 16),
            const FTSectionHeader(
              title: 'Quick Admin Actions',
              subtitle: 'Seed data and automation control shortcuts',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _seed('/admin/demo/seed-nationwide', 'Seed Nationwide'),
                  icon: const Icon(Icons.public_outlined),
                  label: const Text('Seed Nationwide'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _seed(
                      '/admin/demo/seed-leaderboards', 'Seed Leaderboards'),
                  icon: const Icon(Icons.emoji_events_outlined),
                  label: const Text('Seed Leaderboards'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _seed('/admin/autopilot/tick', 'Run Notify Queue Demo'),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Run Notify Queue Demo'),
                ),
                OutlinedButton.icon(
                  onPressed: _toggleAutopilot,
                  icon: const Icon(Icons.toggle_on_outlined),
                  label: const Text('Toggle Autopilot'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
