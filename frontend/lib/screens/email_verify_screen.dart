import 'package:flutter/material.dart';

import '../services/api_service.dart';

class EmailVerifyScreen extends StatefulWidget {
  final String? initialEmail;
  const EmailVerifyScreen({super.key, this.initialEmail});

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  final _emailCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  bool _verified = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final me = await ApiService.getProfile();
      final verified = me['is_verified'] == true || me['email_verified'] == true;
      final email = me['email']?.toString() ?? '';
      if (_emailCtrl.text.trim().isEmpty && email.isNotEmpty) {
        _emailCtrl.text = email;
      }
      if (!mounted) return;
      setState(() {
        _verified = verified;
        _status = verified ? 'Email is verified' : 'Email not verified';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Unable to load status');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await ApiService.verifySend();
      final link = (res['verification_link'] ?? '').toString().trim();
      if (link.isNotEmpty) {
        _toast('Verification link generated. Check logs/inbox.');
      } else {
        _toast('Verification link sent. Check your inbox.');
      }
    } catch (e) {
      _toast('Send failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_loading) return;
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) {
      _toast('Enter the token from the verification link.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.verifyConfirm(token: token);
      _toast('Email verified.');
      await _loadStatus();
    } catch (e) {
      _toast('Verify failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Email')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_status != null) ...[
            Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
          ],
          const Text(
            'Paste the token from your verification link. If you did not receive it, resend a new link.',
            style: TextStyle(height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Verification token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _send,
            child: Text(_loading ? 'Please wait...' : 'Resend verification link'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _loading ? null : _confirm,
            child: const Text('Verify email'),
          ),
          const SizedBox(height: 8),
          if (_verified)
            const Text('Your email is verified.', style: TextStyle(color: Colors.green)),
        ],
      ),
    );
  }
}
