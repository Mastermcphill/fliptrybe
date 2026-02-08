import 'package:flutter/material.dart';

import '../services/api_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _tokenCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (_loading) return;
    final tokenOrCode = _tokenCtrl.text.trim();
    final pw = _passwordCtrl.text.trim();
    final pw2 = _confirmCtrl.text.trim();

    if (tokenOrCode.isEmpty) {
      _toast('Token or code is required.');
      return;
    }
    if (pw.isEmpty || pw.length < 4) {
      _toast('New password is required.');
      return;
    }
    if (pw != pw2) {
      _toast('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);
    try {
      await ApiService.passwordReset(newPassword: pw, token: tokenOrCode);
      _toast('Password reset successful. You can log in now.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('Reset failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: Text(_loading ? 'Please wait...' : 'Reset Password'),
          ),
        ],
      ),
    );
  }
}
