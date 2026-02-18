import 'package:flutter/material.dart';

import '../services/api_service.dart';

class PhoneVerifyScreen extends StatefulWidget {
  const PhoneVerifyScreen({super.key, this.initialPhone});

  final String? initialPhone;

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _verified = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = widget.initialPhone ?? '';
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final me = await ApiService.getProfile();
      final verified = me['is_verified'] == true;
      final phone = (me['phone'] ?? '').toString();
      if (_phoneCtrl.text.trim().isEmpty && phone.isNotEmpty) {
        _phoneCtrl.text = phone;
      }
      if (!mounted) return;
      setState(() {
        _verified = verified;
        _status = verified ? 'Phone is verified' : 'Phone not verified';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Unable to load verification status');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _requestOtp() async {
    if (_loading) return;
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) {
      _toast('Enter your phone number.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.requestPhoneOtp(phone: phone);
      _toast('OTP sent to your phone.');
    } catch (e) {
      _toast('OTP request failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.isEmpty || code.isEmpty) {
      _toast('Enter both phone and OTP code.');
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.verifyPhoneOtp(phone: phone, code: code);
      if (!mounted) return;
      _toast('Phone verified.');
      await _loadStatus();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _toast('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Phone')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_status != null) ...[
            Text(_status!, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
          ],
          const Text(
            'Request an OTP and enter the code to verify your phone.',
            style: TextStyle(height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'OTP code',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _loading ? null : _requestOtp,
            child: Text(_loading ? 'Please wait...' : 'Request OTP'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: _loading ? null : _verifyOtp,
            child: const Text('Verify phone'),
          ),
          if (_verified) ...[
            const SizedBox(height: 8),
            const Text(
              'Your phone is verified.',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ],
      ),
    );
  }
}
