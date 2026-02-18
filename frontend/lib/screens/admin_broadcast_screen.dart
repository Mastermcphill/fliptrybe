import 'package:flutter/material.dart';
import '../services/admin_broadcast_service.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _svc = AdminBroadcastService();
  final _titleCtrl = TextEditingController(text: "FlipTrybe Update");
  final _msgCtrl = TextEditingController(
      text: "Welcome to FlipTrybe. New merchants are live.");
  final _stateCtrl = TextEditingController(text: "");
  final _cityCtrl = TextEditingController(text: "");

  String _channel = "in_app";
  bool _busy = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    _stateCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Broadcast")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
              "Send a broadcast notification. Admin access is required."),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: "Title", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _msgCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: "Message", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _channel,
            decoration: const InputDecoration(
                labelText: "Channel", border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: "in_app", child: Text("In-app")),
              DropdownMenuItem(value: "sms", child: Text("SMS")),
              DropdownMenuItem(
                  value: "whatsapp", child: Text("WhatsApp")),
            ],
            onChanged: (v) => setState(() => _channel = v ?? "in_app"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _stateCtrl,
            decoration: const InputDecoration(
                labelText: "Target state (optional)",
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(
                labelText: "Target city (optional)",
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final title = _titleCtrl.text.trim();
                      final msg = _msgCtrl.text.trim();
                      if (msg.isEmpty) return;

                      setState(() => _busy = true);
                      final ok = await _svc.broadcast(
                        title: title,
                        message: msg,
                        channel: _channel,
                        state: _stateCtrl.text.trim(),
                        city: _cityCtrl.text.trim(),
                      );
                      if (!context.mounted) return;
                      setState(() => _busy = false);

                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Broadcast sent.")));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Broadcast failed.")));
                      }
                    },
              icon: const Icon(Icons.campaign_outlined),
              label: Text(_busy ? "..." : "Send broadcast"),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        // process queued notifications (admin)
                        await _svc.processQueue();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Queue processed.")));
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Process failed.")));
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              icon: const Icon(Icons.playlist_add_check_outlined),
              label: Text(_busy ? "..." : "Process queued notifications"),
            ),
          ),
        ],
      ),
    );
  }
}
