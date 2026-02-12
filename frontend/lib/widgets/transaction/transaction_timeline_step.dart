import 'package:flutter/material.dart';

class TransactionTimelineStep extends StatelessWidget {
  const TransactionTimelineStep({
    super.key,
    required this.title,
    required this.status,
    required this.escrowStatus,
    this.subtitle = '',
    this.notifiedInApp = true,
    this.notifiedSms = false,
    this.notifiedWhatsApp = false,
  });

  final String title;
  final String status;
  final String escrowStatus;
  final String subtitle;
  final bool notifiedInApp;
  final bool notifiedSms;
  final bool notifiedWhatsApp;

  Color _statusColor() {
    final value = status.toLowerCase();
    if (value == 'completed') return Colors.green;
    if (value == 'cancelled') return Colors.redAccent;
    return Colors.orange;
  }

  Widget _channelBadge(String label, bool sent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: sent ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            sent ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 14,
            color: sent ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _statusColor(),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _channelBadge('In-app', notifiedInApp),
                _channelBadge('SMS', notifiedSms),
                _channelBadge('WhatsApp', notifiedWhatsApp),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Escrow: $escrowStatus',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
