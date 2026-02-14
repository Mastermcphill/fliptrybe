class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    required this.channel,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String channel;

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAt,
    bool? isRead,
    String? channel,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAt: createdAt ?? this.createdAt,
      isRead: isRead ?? this.isRead,
      channel: channel ?? this.channel,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'created_at': createdAt.toUtc().toIso8601String(),
      'is_read': isRead,
      'channel': channel,
    };
  }

  static NotificationItem fromJson(Map<String, dynamic> json) {
    final rawId =
        (json['id'] ?? json['notification_id'] ?? '').toString().trim();
    final rawTitle =
        (json['title'] ?? json['subject'] ?? 'Notification').toString();
    final rawBody = (json['body'] ?? json['message'] ?? '').toString();
    final rawChannel = (json['channel'] ?? 'in_app').toString();
    final status = (json['status'] ?? '').toString().toLowerCase();
    final isRead = json['is_read'] == true || status == 'read';
    final createdAtRaw =
        (json['created_at'] ?? json['createdAt'] ?? '').toString();
    final createdAt =
        DateTime.tryParse(createdAtRaw)?.toUtc() ?? DateTime.now().toUtc();

    final id = rawId.isNotEmpty
        ? rawId
        : '${rawTitle.hashCode}_${createdAt.millisecondsSinceEpoch}';

    return NotificationItem(
      id: id,
      title: rawTitle,
      body: rawBody,
      createdAt: createdAt,
      isRead: isRead,
      channel: rawChannel,
    );
  }
}
