import 'package:flutter/material.dart';

import '../services/kyc_service.dart';

class AdminKycReviewScreen extends StatefulWidget {
  const AdminKycReviewScreen({super.key});

  @override
  State<AdminKycReviewScreen> createState() => _AdminKycReviewScreenState();
}

class _AdminKycReviewScreenState extends State<AdminKycReviewScreen> {
  final _svc = KycService();
  late Future<List<dynamic>> _items;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = _svc.adminPending();
  }

  void _reload() {
    setState(() => _items = _svc.adminPending());
  }

  Future<String?> _promptNote(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Note (optional)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Save')),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _setStatus(Map<String, dynamic> item, String status) async {
    if (_busy) return;
    final note =
        await _promptNote(status == 'verified' ? 'Approve KYC' : 'Reject KYC');
    if (!mounted) return;
    if (note == null) return;
    setState(() => _busy = true);
    final ok = await _svc.adminSet(
        userId: item['user_id'] as int, status: status, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Updated' : 'Update failed')));
    if (ok) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KYC Review'),
        actions: [
          IconButton(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh))
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
            return const Center(child: Text('No pending KYC submissions.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final raw = items[i];
              if (raw is! Map) return const SizedBox.shrink();
              final item = Map<String, dynamic>.from(raw);
              final email = (item['email'] ?? '').toString();
              final name = (item['name'] ?? '').toString();
              final idType = (item['id_type'] ?? '').toString();
              final idNum = (item['id_number'] ?? '').toString();

              return Card(
                margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: ListTile(
                  title:
                      Text(email.isEmpty ? 'User #${item['user_id']}' : email),
                  subtitle: Text(
                      '${name.isEmpty ? 'Unknown' : name} • $idType • $idNum'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed:
                            _busy ? null : () => _setStatus(item, 'rejected'),
                        child: const Text('Reject'),
                      ),
                      ElevatedButton(
                        onPressed:
                            _busy ? null : () => _setStatus(item, 'verified'),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
