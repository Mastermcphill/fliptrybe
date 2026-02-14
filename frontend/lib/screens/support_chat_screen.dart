import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../widgets/chat_not_allowed_dialog.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _msgCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  List<dynamic> _items = const [];

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
      final res =
          await ApiClient.instance.dio.get(ApiConfig.api('/support/messages'));
      final data = res.data;
      final items = (data is Map && data['items'] is List)
          ? (data['items'] as List)
          : <dynamic>[];
      if (!mounted) return;
      setState(() => _items = items);
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (ApiService.isChatNotAllowed(data)) {
        await showChatNotAllowedDialog(
          context,
          onChatWithAdmin: _load,
        );
        setState(
            () => _error = 'Direct messaging between users is not allowed.');
        return;
      }
      setState(() => _error = e.toString());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _msgCtrl.text.trim();
    if (body.isEmpty) return;
    setState(() => _loading = true);
    try {
      final res = await ApiClient.instance.dio.post(
        ApiConfig.api('/support/messages'),
        data: {'body': body},
      );
      if (!mounted) return;
      if (res.statusCode != null &&
          res.statusCode! >= 200 &&
          res.statusCode! < 300) {
        _msgCtrl.clear();
        await _load();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Message failed.')));
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      if (ApiService.isChatNotAllowed(data)) {
        await showChatNotAllowedDialog(
          context,
          onChatWithAdmin: _load,
        );
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Message failed: $e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Message failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _bubble(Map<String, dynamic> m) {
    final body = (m['body'] ?? '').toString();
    final role = (m['sender_role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final align = isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isAdmin ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A);
    final bg = isAdmin ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9);
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
          child: Text(body,
              style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Admin'),
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
              padding: const EdgeInsets.all(12),
              children: [
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No messages yet. Say hello to Admin.'),
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
                      labelText: 'Message',
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
