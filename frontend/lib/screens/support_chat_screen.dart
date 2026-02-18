import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/api_service.dart';
import '../widgets/chat_not_allowed_dialog.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({
    super.key,
    this.recipientUserId,
    this.listingId,
    this.title = 'Messages',
    this.initialHint = 'Message',
  });

  final int? recipientUserId;
  final int? listingId;
  final String title;
  final String initialHint;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _msgCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  int? _currentUserId;
  List<dynamic> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadProfileContext();
    _load();
  }

  Future<void> _loadProfileContext() async {
    try {
      final profile = await ApiService.getProfile();
      if (!mounted) return;
      final id = profile['id'] is int
          ? profile['id'] as int
          : int.tryParse('${profile['id'] ?? ''}');
      setState(() => _currentUserId = id);
    } catch (_) {}
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
      if (ApiService.isContactBlocked(data)) {
        setState(() => _error =
            'For safety, contact details cannot be shared in chat. Please keep communication in FlipTrybe.');
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
      final payload = <String, dynamic>{'body': body};
      if (widget.recipientUserId != null && widget.recipientUserId! > 0) {
        payload['user_id'] = widget.recipientUserId;
      }
      if (widget.listingId != null && widget.listingId! > 0) {
        payload['listing_id'] = widget.listingId;
      }
      final res = await ApiClient.instance.dio.post(
        ApiConfig.api('/support/messages'),
        data: payload,
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
      if (ApiService.isContactBlocked(data)) {
        final msg = (data is Map && data['message'] != null)
            ? data['message'].toString()
            : 'For safety, contact details cannot be shared in chat. Please keep communication in FlipTrybe.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
    final senderId = m['sender_id'] is int
        ? m['sender_id'] as int
        : int.tryParse('${m['sender_id'] ?? ''}') ?? 0;
    final fromMe =
        _currentUserId != null && senderId > 0 && senderId == _currentUserId;
    final role = (m['sender_role'] ?? '').toString().toLowerCase();
    final isAdmin = role == 'admin';
    final align = fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isAdmin ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A);
    final bg = fromMe ? const Color(0xFFE0F2FE) : const Color(0xFFF1F5F9);
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

  List<Map<String, dynamic>> _visibleItems(List<Map<String, dynamic>> items) {
    final targetId = widget.recipientUserId;
    final targetListingId = widget.listingId;
    final selfId = _currentUserId;
    if (targetId == null || targetId <= 0 || selfId == null || selfId <= 0) {
      return items;
    }
    return items.where((row) {
      final sender = row['sender_id'] is int
          ? row['sender_id'] as int
          : int.tryParse('${row['sender_id'] ?? ''}') ?? 0;
      final recipient = row['recipient_id'] is int
          ? row['recipient_id'] as int
          : int.tryParse('${row['recipient_id'] ?? ''}') ?? 0;
      final listingId = row['listing_id'] is int
          ? row['listing_id'] as int
          : int.tryParse('${row['listing_id'] ?? ''}');
      final betweenUsers = (sender == selfId && recipient == targetId) ||
          (sender == targetId && recipient == selfId);
      if (!betweenUsers) return false;
      if (targetListingId != null && targetListingId > 0) {
        return listingId == targetListingId;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final rawItems = _items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    final items = _visibleItems(rawItems);
    final emptyText = widget.recipientUserId != null
        ? 'No messages yet. Ask your question and keep communication in-app.'
        : 'No messages yet. Say hello to admin support.';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(emptyText),
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
                    decoration: InputDecoration(
                      labelText: widget.initialHint,
                      border: const OutlineInputBorder(),
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

