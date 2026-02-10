import 'package:flutter/material.dart';

import '../services/admin_role_service.dart';

class AdminRoleApprovalsScreen extends StatefulWidget {
  const AdminRoleApprovalsScreen({super.key});

  @override
  State<AdminRoleApprovalsScreen> createState() => _AdminRoleApprovalsScreenState();
}

class _AdminRoleApprovalsScreenState extends State<AdminRoleApprovalsScreen> {
  final _svc = AdminRoleService();
  late Future<List<dynamic>> _items;
  String _status = 'PENDING';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _items = _svc.pending(status: _status);
  }

  void _reload() {
    setState(() => _items = _svc.pending(status: _status));
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    if (_busy) return;
    final reqId = item['id'] is int ? item['id'] as int : int.tryParse((item['id'] ?? '').toString());
    if (reqId == null) return;
    setState(() => _busy = true);
    final res = await _svc.approve(requestId: reqId);
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? (ok ? 'Approved' : 'Approve failed')).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (ok) _reload();
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    if (_busy) return;
    final reqId = item['id'] is int ? item['id'] as int : int.tryParse((item['id'] ?? '').toString());
    if (reqId == null) return;
    setState(() => _busy = true);
    final res = await _svc.reject(requestId: reqId);
    if (!mounted) return;
    setState(() => _busy = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? (ok ? 'Rejected' : 'Reject failed')).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (ok) _reload();
  }

  Widget _statusChip(String value) {
    return ChoiceChip(
      label: Text(value[0] + value.substring(1).toLowerCase()),
      selected: _status == value,
      onSelected: (selected) {
        if (!selected) return;
        setState(() {
          _status = value;
          _items = _svc.pending(status: _status);
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Role Approvals'),
        actions: [IconButton(onPressed: _busy ? null : _reload, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                _statusChip('PENDING'),
                _statusChip('APPROVED'),
                _statusChip('REJECTED'),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return Center(child: Text('No ${_status.toLowerCase()} approvals.'));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final raw = items[i];
                    if (raw is! Map) return const SizedBox.shrink();
                    final item = Map<String, dynamic>.from(raw);
                    final requestedRole = (item['requested_role'] ?? '').toString();
                    final currentRole = (item['current_role'] ?? '').toString();
                    final status = (item['status'] ?? '').toString();
                    final reason = (item['reason'] ?? '').toString();
                    final createdAt = (item['created_at'] ?? '').toString();
                    final userId = (item['user_id'] ?? '').toString();

                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: ListTile(
                        title: Text('User #$userId • $requestedRole'),
                        subtitle: Text(
                          'Current: $currentRole\nStatus: $status\n$createdAt${reason.isNotEmpty ? '\nReason: $reason' : ''}',
                        ),
                        trailing: _status != 'PENDING'
                            ? null
                            : Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: _busy ? null : () => _reject(item),
                                    child: const Text('Reject'),
                                  ),
                                  ElevatedButton(
                                    onPressed: _busy ? null : () => _approve(item),
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
          ),
        ],
      ),
    );
  }
}
