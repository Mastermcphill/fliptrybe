import 'package:flutter/material.dart';

import '../domain/models/notification_item.dart';
import '../services/notification_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/ui_feedback.dart';

class NotificationsInboxScreen extends StatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  final NotificationService _svc = NotificationService.instance;

  bool _loading = true;
  String? _error;
  List<NotificationItem> _items = const <NotificationItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool hard = false}) async {
    setState(() {
      _loading = hard || _items.isEmpty;
      _error = null;
    });
    try {
      final data = await _svc.loadInbox(refresh: true);
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load notifications right now.';
        _loading = false;
      });
    }
  }

  Future<void> _markRead(NotificationItem item) async {
    if (item.isRead) return;
    final synced = await _svc.markAsRead(item.id);
    if (!mounted) return;
    setState(() {
      _items = _items
          .map((row) => row.id == item.id ? row.copyWith(isRead: true) : row)
          .toList(growable: false);
    });
    if (!synced) {
      UIFeedback.showErrorSnack(
        context,
        'Marked locally. Server sync pending, please refresh later.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Notifications',
      onRefresh: () => _load(hard: true),
      actions: [
        IconButton(
          tooltip: 'Mark all read',
          onPressed: _items.isEmpty
              ? null
              : () async {
                  await _svc.markAllRead();
                  if (!mounted) return;
                  setState(() {
                    _items = _items
                        .map((item) => item.copyWith(isRead: true))
                        .toList(growable: false);
                  });
                },
          icon: const Icon(Icons.done_all_outlined),
        ),
      ],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: () => _load(hard: true),
        empty: _items.isEmpty,
        loadingState: FTSkeletonList(
          itemCount: 6,
          itemBuilder: (_, __) => const FTSkeletonCard(height: 92),
        ),
        emptyState: FTEmptyState(
          icon: Icons.notifications_none,
          title: 'No notifications yet',
          subtitle:
              'We will notify you about orders, payouts, and role updates.',
          primaryCtaText: 'Refresh',
          onPrimaryCta: () => _load(hard: true),
        ),
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final item = _items[i];
            return FTCard(
              color: item.isRead
                  ? null
                  : Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.25),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _markRead(item),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        item.channel == 'sms'
                            ? Icons.sms_outlined
                            : item.channel == 'whatsapp'
                                ? Icons.chat_outlined
                                : Icons.notifications_active_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                if (!item.isRead) FTBadge(text: 'NEW'),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.createdAt.toLocal().toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
