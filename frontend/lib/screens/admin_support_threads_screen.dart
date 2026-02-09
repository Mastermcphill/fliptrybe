import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import 'admin_support_thread_screen.dart';

class AdminSupportThreadsScreen extends StatefulWidget {
  const AdminSupportThreadsScreen({super.key});

  @override
  State<AdminSupportThreadsScreen> createState() => _AdminSupportThreadsScreenState();
}

class _AdminSupportThreadsScreenState extends State<AdminSupportThreadsScreen> {
  bool _loading = false;
  String? _error;
  List<dynamic> _threads = const [];

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
      final res = await ApiClient.instance.dio.get(ApiConfig.api('/admin/support/threads'));
      final data = res.data;
      final items = (data is Map && data['threads'] is List) ? (data['threads'] as List) : <dynamic>[];
      if (!mounted) return;
      setState(() => _threads = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Threads'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Load failed: $_error', style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _threads.length,
              itemBuilder: (context, i) {
                final raw = _threads[i];
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw as Map);
                final id = m['user_id'];
                final name = (m['name'] ?? '').toString();
                final email = (m['email'] ?? '').toString();
                final count = (m['count'] ?? 0).toString();
                final lastAt = (m['last_at'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ListTile(
                    title: Text(name.isEmpty ? email : name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(email.isEmpty ? lastAt : '$email\n$lastAt'),
                    trailing: Chip(label: Text('Msg: $count')),
                    onTap: () {
                      final userId = id is int ? id : int.tryParse(id?.toString() ?? '');
                      if (userId == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AdminSupportThreadScreen(userId: userId, userEmail: email)),
                      );
                    },
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
