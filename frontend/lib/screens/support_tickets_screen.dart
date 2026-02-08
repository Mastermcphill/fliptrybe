import 'package:flutter/material.dart';

import '../services/support_service.dart';
import '../services/api_service.dart';
import '../widgets/chat_not_allowed_dialog.dart';

class SupportTicketsScreen extends StatefulWidget {
  const SupportTicketsScreen({super.key});

  @override
  State<SupportTicketsScreen> createState() => _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends State<SupportTicketsScreen> {
  final _svc = SupportService();

  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _svc.listTickets();
  }

  void _reload() {
    setState(() => _items = _svc.listTickets());
  }

  Future<void> _newTicket({String? presetSubject}) async {
    final subjectCtrl = TextEditingController(text: presetSubject ?? '');
    final msgCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New ticket'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subjectCtrl,
                decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );

    if (ok != true) return;

    final subject = subjectCtrl.text.trim();
    final message = msgCtrl.text.trim();
    if (subject.isEmpty || message.isEmpty) return;

    await _submitTicket(subject: subject, message: message);
  }

  Future<void> _contactAdmin() async {
    await _newTicket(presetSubject: 'Help Request');
  }

  Future<void> _openDispute() async {
    final orderCtrl = TextEditingController();
    final msgCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open Dispute'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orderCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Order ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );

    if (ok != true) return;
    final orderId = orderCtrl.text.trim();
    final reason = msgCtrl.text.trim();
    if (orderId.isEmpty || reason.isEmpty) return;

    await _submitTicket(subject: 'Dispute: Order #$orderId', message: reason);
  }

  Future<void> _submitTicket({required String subject, required String message}) async {
    final res = await _svc.createTicket(subject: subject, message: message);
    if (!mounted) return;
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? (ok ? 'Ticket created.' : 'Request failed')).toString();
    if (!ok && ApiService.isChatNotAllowed(res)) {
      await showChatNotAllowedDialog(context, onChatWithAdmin: _contactAdmin);
      return;
    }
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _chip(String status) {
    final s = status.toLowerCase();
    IconData icon = Icons.flag_outlined;
    if (s == 'resolved') icon = Icons.check_circle_outline;
    if (s == 'in_progress') icon = Icons.autorenew;
    if (s == 'closed') icon = Icons.lock_outline;

    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(status),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Disputes'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _newTicket,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          final faqItems = const [
            'Use “Contact Admin” for urgent help.',
            'For disputes, include the Order ID and a short reason.',
            'Refunds are evaluated after verification.',
          ];

          final ticketCards = items.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final m = Map<String, dynamic>.from(raw as Map);
            return Card(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: ListTile(
                title: Text((m['subject'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text((m['message'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: _chip((m['status'] ?? 'open').toString()),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text((m['subject'] ?? '').toString()),
                      content: Text((m['message'] ?? '').toString()),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                      ],
                    ),
                  );
                },
              ),
            );
          }).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Card(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Quick Help', style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      ...faqItems.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('- $t'),
                      )),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _contactAdmin,
                              child: const Text('Contact Admin'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _openDispute,
                              child: const Text('Open Dispute'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No tickets yet. Tap + to create one.'),
                )
              else
                ...ticketCards,
            ],
          );
        },
      ),
    );
  }
}
