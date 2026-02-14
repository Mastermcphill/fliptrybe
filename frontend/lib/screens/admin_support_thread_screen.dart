import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/support_service.dart';

class AdminSupportThreadScreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  final SupportService? supportService;
  final bool forceAdmin;

  const AdminSupportThreadScreen(
      {super.key,
      required this.userId,
      this.userEmail = '',
      this.supportService,
      this.forceAdmin = false});

  @override
  State<AdminSupportThreadScreen> createState() =>
      _AdminSupportThreadScreenState();
}

class _AdminSupportThreadScreenState extends State<AdminSupportThreadScreen> {
  late final SupportService _supportService;
  bool _authChecking = true;
  bool _isAdmin = false;
  bool _loading = false;
  bool _canSend = false;
  String? _error;
  List<dynamic> _items = const [];
  final _msgCtrl = TextEditingController();
  final _listCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _supportService = widget.supportService ?? SupportService();
    _msgCtrl.addListener(_syncSendState);
    if (widget.forceAdmin) {
      _isAdmin = true;
      _authChecking = false;
      _load();
      return;
    }
    _ensureAdmin();
  }

  @override
  void dispose() {
    _msgCtrl.removeListener(_syncSendState);
    _msgCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _syncSendState() {
    final canSendNow = _msgCtrl.text.trim().isNotEmpty && !_loading;
    if (canSendNow == _canSend) return;
    setState(() => _canSend = canSendNow);
  }

  void _scrollToBottom() {
    if (!_listCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listCtrl.hasClients) return;
      _listCtrl.animateTo(
        _listCtrl.position.maxScrollExtent + 64,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
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
      final items = await _supportService.adminThreadMessages(widget.userId);
      if (!mounted) return;
      setState(() => _items = items);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncSendState();
      }
    }
  }

  Future<void> _send() async {
    if (!_isAdmin) return;
    final body = _msgCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _loading = true;
      _canSend = false;
    });
    try {
      final res = await _supportService.adminReply(
        threadId: widget.userId,
        body: body,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        final created = res['message'];
        _msgCtrl.clear();
        if (created is Map) {
          final next = List<Map<String, dynamic>>.from(
            _items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
          )..add(Map<String, dynamic>.from(created));
          setState(() => _items = next);
          _scrollToBottom();
        } else {
          await _load();
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Send failed.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _syncSendState();
      }
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final body = (m['body'] ?? '').toString();
    final role = (m['sender_role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final cs = Theme.of(context).colorScheme;
    final align = isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = isAdmin ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = isAdmin ? cs.onPrimaryContainer : cs.onSurface;
    final label = isAdmin ? 'Admin' : 'User';
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
          child: Column(
            crossAxisAlignment: align,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
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
    final items = _items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userEmail.isEmpty ? 'Thread' : widget.userEmail),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Load failed: $_error',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Expanded(
            child: ListView(
              controller: _listCtrl,
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
                  onPressed: _canSend ? _send : null,
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
