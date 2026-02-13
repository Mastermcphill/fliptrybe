import 'package:flutter/material.dart';

import '../services/admin_notify_queue_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';

class AdminNotifyQueueScreen extends StatefulWidget {
  const AdminNotifyQueueScreen({super.key});

  @override
  State<AdminNotifyQueueScreen> createState() => _AdminNotifyQueueScreenState();
}

class _AdminNotifyQueueScreenState extends State<AdminNotifyQueueScreen> {
  final _svc = AdminNotifyQueueService();
  final _channelCtrl = TextEditingController();
  String _status = '';
  bool _loading = false;
  bool _busy = false;
  String? _error;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _channelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _svc.list(channel: _channelCtrl.text.trim(), status: _status.trim());
      if (!mounted) return;
      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(Future<Map<String, dynamic>> Function() action, String okText) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await action();
      if (!mounted) return;
      final ok = res['ok'] == true;
      final msg = ok ? okText : ((res['message'] ?? res['error'] ?? 'Action failed').toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _value(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Notify Queue',
      actions: [
        TextButton(
          onPressed: _loading || _busy
              ? null
              : () => _runAction(
                    () => _svc.requeueDead(channel: _channelCtrl.text.trim()),
                    'Dead messages requeued',
                  ),
          child: const Text('Requeue dead'),
        ),
      ],
      onRefresh: _loading || _busy ? null : _load,
      child: Column(
        children: [
          FTCard(
            child: Row(
              children: [
                Expanded(
                  child: FTInput(
                    controller: _channelCtrl,
                    label: 'Channel',
                    hint: 'email, sms, push',
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: AppTokens.s12),
                DropdownButton<String>(
                  value: _status,
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
                    DropdownMenuItem(value: 'queued', child: Text('Queued')),
                    DropdownMenuItem(value: 'sent', child: Text('Sent')),
                    DropdownMenuItem(value: 'failed', child: Text('Failed')),
                    DropdownMenuItem(value: 'dead', child: Text('Dead')),
                  ],
                  onChanged: (v) {
                    setState(() => _status = v ?? '');
                    _load();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s12),
          Expanded(
            child: FTLoadStateLayout(
              loading: _loading,
              error: _error,
              onRetry: _load,
              empty: _items.isEmpty,
              loadingState: ListView(
                children: const [
                  FTListCardSkeleton(withImage: false),
                  SizedBox(height: AppTokens.s12),
                  FTListCardSkeleton(withImage: false),
                  SizedBox(height: AppTokens.s12),
                  FTListCardSkeleton(withImage: false),
                ],
              ),
              emptyState: FTEmptyState(
                icon: Icons.notifications_none_outlined,
                title: 'No queue items found',
                subtitle: 'Retry after notifications are queued.',
                actionLabel: 'Refresh',
                onAction: _load,
              ),
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppTokens.s8),
                itemBuilder: (_, i) {
                  final raw = _items[i];
                  if (raw is! Map) return const SizedBox.shrink();
                  final row = Map<String, dynamic>.from(raw);
                  final id = int.tryParse(_value(row['id'])) ?? 0;
                  final status = _value(row['status']).toLowerCase();
                  final subtitle =
                      '${_value(row['channel'])} -> ${_value(row['to'])}\nstatus: ${_value(row['status'])}  attempts: ${_value(row['attempt_count'])}/${_value(row['max_attempts'])}\n${_value(row['last_error'])}';

                  return FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FTTile(
                          title: 'Queue #$id',
                          subtitle: subtitle,
                          trailing: FTBadge(text: status.toUpperCase()),
                        ),
                        const SizedBox(height: AppTokens.s8),
                        Wrap(
                          spacing: AppTokens.s8,
                          children: [
                            if (status != 'sent')
                              FTButton(
                                label: 'Mark sent',
                                icon: Icons.done_all,
                                variant: FTButtonVariant.secondary,
                                onPressed: _busy || id <= 0
                                    ? null
                                    : () => _runAction(
                                          () => _svc.markSent(id),
                                          'Marked as sent',
                                        ),
                              ),
                            if (status == 'failed' || status == 'dead')
                              FTButton(
                                label: 'Requeue',
                                icon: Icons.replay,
                                variant: FTButtonVariant.ghost,
                                onPressed: _busy || id <= 0
                                    ? null
                                    : () => _runAction(
                                          () => _svc.requeue(id),
                                          'Requeued',
                                        ),
                              ),
                            if (status != 'sent')
                              FTButton(
                                label: 'Retry now',
                                icon: Icons.play_circle_outline,
                                variant: FTButtonVariant.primary,
                                onPressed: _busy || id <= 0
                                    ? null
                                    : () => _runAction(
                                          () => _svc.retryNow(id),
                                          'Retry queued',
                                        ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
