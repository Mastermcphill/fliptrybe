import 'package:flutter/material.dart';

import '../services/admin_notify_queue_service.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notify Queue'),
        actions: [
          IconButton(onPressed: _loading || _busy ? null : _load, icon: const Icon(Icons.refresh)),
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
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _channelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Channel',
                      hintText: 'email, sms, push',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
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
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          Expanded(
            child: _items.isEmpty && !_loading
                ? const Center(child: Text('No queue items found.'))
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final raw = _items[i];
                      if (raw is! Map) return const SizedBox.shrink();
                      final row = Map<String, dynamic>.from(raw);
                      final id = int.tryParse(_value(row['id'])) ?? 0;
                      final status = _value(row['status']).toLowerCase();
                      final subtitle =
                          '${_value(row['channel'])} -> ${_value(row['to'])}\nstatus: ${_value(row['status'])}  attempts: ${_value(row['attempt_count'])}/${_value(row['max_attempts'])}\n${_value(row['last_error'])}';

                      return Card(
                        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: ListTile(
                          title: Text('Queue #$id'),
                          subtitle: Text(subtitle),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              if (status != 'sent')
                                IconButton(
                                  tooltip: 'Mark sent',
                                  onPressed: _busy || id <= 0
                                      ? null
                                      : () => _runAction(() => _svc.markSent(id), 'Marked as sent'),
                                  icon: const Icon(Icons.done_all),
                                ),
                              if (status == 'failed' || status == 'dead')
                                IconButton(
                                  tooltip: 'Requeue',
                                  onPressed: _busy || id <= 0
                                      ? null
                                      : () => _runAction(() => _svc.requeue(id), 'Requeued'),
                                  icon: const Icon(Icons.replay),
                                ),
                              if (status != 'sent')
                                IconButton(
                                  tooltip: 'Retry now',
                                  onPressed: _busy || id <= 0
                                      ? null
                                      : () => _runAction(() => _svc.retryNow(id), 'Retry queued'),
                                  icon: const Icon(Icons.play_circle_outline),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
