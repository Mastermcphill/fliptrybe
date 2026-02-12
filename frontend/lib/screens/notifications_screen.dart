import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _svc = NotificationService();
  late Future<List<dynamic>> _future;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _svc.inbox();
  }

  void _reload() => setState(() => _future = _svc.inbox());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            tooltip: 'Send test',
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    final ok = await _svc.flushDemo();
                    if (!context.mounted) return;
                    setState(() => _busy = false);
                    if (ok) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Sent (demo)')));
                      _reload();
                    } else {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Failed.')));
                    }
                  },
            icon: const Icon(Icons.send_outlined),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No notifications yet.')),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final raw = items[i];
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw);
                final title = (m['title'] ?? '').toString();
                final msg = (m['message'] ?? '').toString();
                final channel = (m['channel'] ?? '').toString();
                final status = (m['status'] ?? '').toString();
                final when = (m['created_at'] ?? '').toString();

                return Card(
                  child: ListTile(
                    leading: Icon(channel == 'sms'
                        ? Icons.sms_outlined
                        : channel == 'whatsapp'
                            ? Icons.chat_outlined
                            : Icons.notifications_outlined),
                    title: Text(title.isEmpty ? 'Notification' : title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('$msg\n$channel - $status - $when'),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
