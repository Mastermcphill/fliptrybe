import 'package:flutter/material.dart';

import '../services/admin_ops_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';

class AdminSystemHealthScreen extends StatefulWidget {
  const AdminSystemHealthScreen({super.key});

  @override
  State<AdminSystemHealthScreen> createState() =>
      _AdminSystemHealthScreenState();
}

class _AdminSystemHealthScreenState extends State<AdminSystemHealthScreen> {
  final _svc = AdminOpsService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _health = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await _svc.healthSummary();
      if (!mounted) return;
      setState(() {
        _health = payload;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load system health.';
        _loading = false;
      });
    }
  }

  Widget _statusBadge({
    required String label,
    required bool ok,
  }) {
    return FTBadge(
      text: '$label: ${ok ? 'OK' : 'WARN'}',
      backgroundColor: ok
          ? Theme.of(context).colorScheme.secondaryContainer
          : Theme.of(context).colorScheme.errorContainer,
      textColor: ok
          ? Theme.of(context).colorScheme.onSecondaryContainer
          : Theme.of(context).colorScheme.onErrorContainer,
    );
  }

  int _asInt(String key) => int.tryParse('${_health[key] ?? 0}') ?? 0;

  bool _notifyOk() => _asInt('notify_queue_failed') == 0;
  bool _payoutOk() => _asInt('payouts_pending_count') < 50;
  bool _eventsOk() => _asInt('events_last_1h_errors') == 0;

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'System Health',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _health.isEmpty,
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
        emptyState: FTEmptyState(
          icon: Icons.monitor_heart_outlined,
          title: 'No health data yet',
          subtitle: 'Run a manual refresh to fetch latest runtime signals.',
          actionLabel: 'Refresh',
          onAction: _load,
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: FTMetricTile(
                    label: 'Queue Pending',
                    value: '${_asInt('notify_queue_pending')}',
                    subtitle: 'Failed: ${_asInt('notify_queue_failed')}',
                    icon: Icons.queue_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTMetricTile(
                    label: 'Payout Backlog',
                    value: '${_asInt('payouts_pending_count')}',
                    subtitle:
                        'Oldest age: ${_health['payouts_oldest_age_sec'] ?? '-'}s',
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FTMetricTile(
                    label: 'Escrow Pending',
                    value: '${_asInt('escrow_pending_settlements_count')}',
                    subtitle:
                        'Runner OK: ${_health['escrow_runner_last_ok'] ?? 'n/a'}',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTMetricTile(
                    label: 'Events Errors (1h)',
                    value: '${_asInt('events_last_1h_errors')}',
                    subtitle: '24h: ${_asInt('events_last_24h_errors')}',
                    icon: Icons.error_outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FTSectionContainer(
              title: 'Runtime Status',
              subtitle: 'Current integrations and recent worker execution.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusBadge(label: 'Notify Queue', ok: _notifyOk()),
                      _statusBadge(label: 'Payout Backlog', ok: _payoutOk()),
                      _statusBadge(label: 'Event Errors', ok: _eventsOk()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Server time: ${_health['server_time'] ?? '-'}'),
                  Text('Git SHA: ${_health['git_sha'] ?? '-'}'),
                  Text('Alembic head: ${_health['alembic_head'] ?? '-'}'),
                  Text(
                    'Escrow runner last run: ${_health['escrow_runner_last_run_at'] ?? 'none'}',
                  ),
                  Text(
                    'Escrow runner last error: ${(_health['escrow_runner_last_error'] ?? '').toString().isEmpty ? 'none' : _health['escrow_runner_last_error']}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FTSectionContainer(
              title: 'Integrations',
              subtitle: 'Operational toggles currently active.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paystack mode: ${_health['paystack_mode'] ?? '-'}'),
                  Text('Termii enabled: ${_health['termii_enabled'] ?? false}'),
                  Text(
                      'Cloudinary enabled: ${_health['cloudinary_enabled'] ?? false}'),
                  Text(
                      'Oldest notify age (sec): ${_health['oldest_pending_age_sec'] ?? 'n/a'}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
