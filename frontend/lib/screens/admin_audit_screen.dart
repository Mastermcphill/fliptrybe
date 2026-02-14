import 'package:flutter/material.dart';

import '../services/admin_audit_service.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  final _svc = AdminAuditService();
  final _action = TextEditingController();
  bool _loading = true;
  List<dynamic> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.list(action: _action.text.trim());
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin: Audit Logs"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _action,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Filter by action (optional)",
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _load, child: const Text("Search")),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _rows[i] is Map
                          ? Map<String, dynamic>.from(_rows[i])
                          : <String, dynamic>{};
                      return ListTile(
                        title: Text(r["action"]?.toString() ?? "-"),
                        subtitle: Text(
                          "at ${r["created_at"]?.toString() ?? "-"}\nmeta: ${r["meta"]?.toString() ?? ""}",
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
