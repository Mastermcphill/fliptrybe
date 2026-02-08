import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import '../services/api_service.dart';

class MoneyBoxAutosaveScreen extends StatefulWidget {
  const MoneyBoxAutosaveScreen({super.key});

  @override
  State<MoneyBoxAutosaveScreen> createState() => _MoneyBoxAutosaveScreenState();
}

class _MoneyBoxAutosaveScreenState extends State<MoneyBoxAutosaveScreen> {
  final _svc = MoneyBoxService();
  int _percent = 5;
  bool _loading = false;

  bool _isVerifyMessage(String msg) {
    final m = msg.toLowerCase();
    return m.contains('verify your email') || m.contains('email verification required');
  }

  Future<void> _showVerifyDialog(String msg) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Email verification required'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await ApiService.verifySend();
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Verification email sent')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Resend failed: $e')),
                  );
                }
              },
              child: const Text('Resend verification'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    if (_loading) return;
    setState(() => _loading = true);
    final res = await _svc.setAutosave(_percent);
    if (!mounted) return;
    setState(() => _loading = false);
    final ok = res['ok'] == true;
    final msg = (res['message'] ?? res['error'] ?? '').toString();
    if (!ok) {
      final showMsg = msg.isNotEmpty ? msg : 'Request failed';
      if (_isVerifyMessage(showMsg)) {
        await _showVerifyDialog(showMsg);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(showMsg)),
      );
      return;
    }
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Autosave')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Autosave moves a percentage of each commission credit into MoneyBox (1% - 30%).',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text('Percent: $_percent%'),
            Slider(
              value: _percent.toDouble(),
              min: 0,
              max: 30,
              divisions: 30,
              label: '$_percent%',
              onChanged: _loading ? null : (v) => setState(() => _percent = v.round()),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: Text(_loading ? 'Saving...' : 'Save Autosave'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
