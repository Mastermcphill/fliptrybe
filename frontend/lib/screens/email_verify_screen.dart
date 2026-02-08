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
  final _codeCtrl = TextEditingController();
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
      await ApiService.verifySend();
      _toast('If the account exists, a verification message was sent.');
    } catch (e) {
      _toast('Send failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_loading) return;
    final codeOrToken = _codeCtrl.text.trim();
    if (codeOrToken.isEmpty) {
      _toast('Enter the code or token.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.verifyConfirm(token: codeOrToken);
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
    _codeCtrl.dispose();
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
          TextField(
            controller: _emailCtrl,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            decoration: const InputDecoration(
              labelText: 'Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _send,
            child: Text(_loading ? 'Please wait...' : 'Send Verification'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _loading ? null : _confirm,
            child: const Text('Confirm Verification'),
          ),
          const SizedBox(height: 8),
          if (_verified)
            const Text('Your email is verified.', style: TextStyle(color: Colors.green)),
        ],
      ),
    );
  }
}
