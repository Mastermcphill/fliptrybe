import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() => _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  final _svc = NotificationService();
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _svc.inbox();
  }

  void _reload() => setState(() => _items = _svc.inbox());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final raw = items[i];
              if (raw is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(raw);

              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text((m['title'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text((m['body'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
