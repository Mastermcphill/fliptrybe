import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';

class AdminSupportThreadScreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  const AdminSupportThreadScreen({super.key, required this.userId, this.userEmail = ''});

  @override
  State<AdminSupportThreadScreen> createState() => _AdminSupportThreadScreenState();
}

class _AdminSupportThreadScreenState extends State<AdminSupportThreadScreen> {
  bool _authChecking = true;
  bool _isAdmin = false;
  bool _loading = false;
  String? _error;
  List<dynamic> _items = const [];
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ensureAdmin();
  }

  Future<void> _ensureAdmin() async {
    try {
      final me = await ApiService.getProfile();
      final role = (me['role'] ?? '').toString().trim().toLowerCase();
      if (!mounted) return;
      if (role == 'admin') {
        setState(() {
          _isAdmin = true;
          _authChecking = false;
        });
        await _load();
        return;
      }
      setState(() {
        _authChecking = false;
        _isAdmin = false;
        _error = 'Admin access required.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authChecking = false;
        _isAdmin = false;
        _error = 'Unable to verify admin access: $e';
      });
    }
  }

  Future<void> _load() async {
    if (!_isAdmin) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.instance.dio.get(ApiConfig.api('/admin/support/messages/${widget.userId}'));
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

  Future<void> _send() async {
    if (!_isAdmin) return;
    final body = _msgCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.dio.post(
        ApiConfig.api('/admin/support/messages/${widget.userId}'),
        data: {'body': body},
      );
      if (!mounted) return;
      if (res.statusCode != null && res.statusCode! >= 200 && res.statusCode! < 300) {
        _msgCtrl.clear();
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Send failed.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final body = (m['body'] ?? '').toString();
    final role = (m['sender_role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final align = isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isAdmin ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9);
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(body, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_authChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Thread')),
        body: Center(child: Text(_error ?? 'Admin access required.')),
      );
    }
    final items = _items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userEmail.isEmpty ? 'Thread' : widget.userEmail),
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
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No messages yet.'),
                  )
                else
                  ...items.map(_bubble),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Reply',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _loading ? null : _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
