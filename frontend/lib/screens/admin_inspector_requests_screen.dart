import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';

class AdminInspectorRequestsScreen extends StatefulWidget {
  const AdminInspectorRequestsScreen({super.key});

  @override
  State<AdminInspectorRequestsScreen> createState() => _AdminInspectorRequestsScreenState();
}

class _AdminInspectorRequestsScreenState extends State<AdminInspectorRequestsScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _items = const [];
  String _status = "pending";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio.get(ApiConfig.api('/admin/inspector-requests?status=$_status'));
      final data = res.data;
      final items = (data is Map && data['items'] is List) ? (data['items'] as List) : <dynamic>[];
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int reqId) async {
    try {
      final res = await ApiClient.instance.dio.post(ApiConfig.api('/admin/inspector-requests/$reqId/approve'));
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        final data = res.data;
        final created = (data is Map && data['created'] != null) ? data['created'].toString() : '';
        final user = (data is Map && data['user'] is Map) ? data['user'] as Map : null;
        final userId = user != null ? user['id'] : null;
        if (mounted) {
          final msg = userId != null ? 'Approved as user #$userId (created: $created)' : 'Approved';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        }
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Approve failed')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approve failed: $e')));
    }
  }

  Future<void> _reject(int reqId) async {
    try {
      final res = await ApiClient.instance.dio.post(ApiConfig.api('/admin/inspector-requests/$reqId/reject'));
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reject failed')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reject failed: $e')));
    }
  }

  Widget _filterChip(String value, String label) {
    final selected = _status == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        if (!v) return;
        setState(() => _status = value);
        _load();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Requests'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                _filterChip("pending", "Pending"),
                _filterChip("approved", "Approved"),
                _filterChip("rejected", "Rejected"),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Load failed: $_error', style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final raw = _items[i];
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw as Map);
                final id = m['id'];
                final name = (m['name'] ?? '').toString();
                final email = (m['email'] ?? '').toString();
                final phone = (m['phone'] ?? '').toString();
                final notes = (m['notes'] ?? '').toString();
                final status = (m['status'] ?? '').toString();
                final decidedBy = (m['decided_by'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ListTile(
                    title: Text(name.isEmpty ? email : name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('$email\n$phone\n$notes\nstatus: $status${decidedBy.isNotEmpty ? " · decided_by: $decidedBy" : ""}'),
                    isThreeLine: true,
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        if (_status == "pending")
                          IconButton(
                            onPressed: () {
                              final reqId = id is int ? id : int.tryParse(id?.toString() ?? '');
                              if (reqId != null) _approve(reqId);
                            },
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                        if (_status == "pending")
                          IconButton(
                            onPressed: () {
                              final reqId = id is int ? id : int.tryParse(id?.toString() ?? '');
                              if (reqId != null) _reject(reqId);
                            },
                            icon: const Icon(Icons.cancel_outlined),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
