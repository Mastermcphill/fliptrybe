import 'package:flutter/material.dart';

import '../services/inspector_service.dart';
import '../services/auth_service.dart';
import 'moneybox_dashboard_screen.dart';
import 'pending_approval_screen.dart';
import '../utils/auth_navigation.dart';

class InspectorDashboardScreen extends StatefulWidget {
  const InspectorDashboardScreen({super.key});

  @override
  State<InspectorDashboardScreen> createState() =>
      _InspectorDashboardScreenState();
}

class _InspectorDashboardScreenState extends State<InspectorDashboardScreen> {
  final _svc = InspectorService();
  final _auth = AuthService();
  late Future<List<dynamic>> _data;
  bool _signingOut = false;
  String? _serviceInfo;

  @override
  void initState() {
    super.initState();
    _data = _loadAssignments();
    _guardPending();
  }

  Future<void> _guardPending() async {
    final profile = await _auth.me();
    final status =
        (profile?['role_status'] ?? 'approved').toString().toLowerCase();
    final role = (profile?['role'] ?? 'inspector').toString();
    if (!mounted) return;
    if (status == 'pending') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => PendingApprovalScreen(role: role)),
      );
    }
  }

  void _reload() {
    setState(() => _data = _loadAssignments());
  }

  Future<List<dynamic>> _loadAssignments() async {
    final items = await _svc.assignments();
    if (!mounted) return items;
    setState(() => _serviceInfo = _svc.lastInfo);
    return items;
  }

  Future<bool> _confirmSignOut() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleSignOut() async {
    if (_signingOut) return;
    final confirmed = await _confirmSignOut();
    if (!confirmed) return;
    setState(() => _signingOut = true);
    try {
      await logoutToLanding(context);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _submit(BuildContext context, Map<String, dynamic> item) async {
    final reportCtrl = TextEditingController();
    String verdict = 'pass';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submit Report'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: verdict,
              decoration: const InputDecoration(labelText: 'Verdict'),
              items: const [
                DropdownMenuItem(value: 'pass', child: Text('Pass')),
                DropdownMenuItem(value: 'fail', child: Text('Fail')),
              ],
              onChanged: (v) => verdict = v ?? 'pass',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reportCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Report',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Submit')),
        ],
      ),
    );

    if (ok != true) return;
    final assignmentId = item['id'];
    if (assignmentId is! int) return;

    final success = await _svc.submitReport(assignmentId,
        verdict: verdict, report: reportCtrl.text.trim());
    if (!mounted) return;
    setState(() => _serviceInfo = _svc.lastInfo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(success
              ? 'Report submitted'
              : (_svc.lastInfo ?? 'Submit failed'))),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Hub'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          TextButton(
            onPressed: _signingOut ? null : _handleSignOut,
            child: Text(
              _signingOut ? 'Signing out...' : 'Sign out',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: const Text('MoneyBox'),
                  subtitle: const Text('Save from commission earnings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MoneyBoxDashboardScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if ((_serviceInfo ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _serviceInfo!,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
              const Text('Assigned Inspections',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No assigned inspections yet.'),
                ))
              else
                ...items.map((raw) {
                  final item = Map<String, dynamic>.from(raw as Map);
                  final title = (item['listing_title'] ?? 'Order').toString();
                  final status = (item['status'] ?? 'assigned').toString();
                  final orderId = item['order_id']?.toString() ?? '-';
                  final price = item['price']?.toString() ?? '-';
                  return Card(
                    child: ListTile(
                      title: Text('$title (Order #$orderId)'),
                      subtitle: Text('Status: $status • ₦$price'),
                      trailing: TextButton(
                        onPressed: ((_serviceInfo ?? '')
                                .toLowerCase()
                                .contains('not available'))
                            ? null
                            : () => _submit(context, item),
                        child: const Text('Submit'),
                      ),
                    ),
                  );
                }).toList(),
            ],
          );
        },
      ),
    );
  }
}
