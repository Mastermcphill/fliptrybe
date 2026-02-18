import 'package:flutter/material.dart';

import '../services/moneybox_service.dart';
import '../services/api_service.dart';
import '../widgets/phone_verification_dialog.dart';
import 'kyc_screen.dart';

class MoneyBoxAutosaveScreen extends StatefulWidget {
  const MoneyBoxAutosaveScreen({super.key});

  @override
  State<MoneyBoxAutosaveScreen> createState() => _MoneyBoxAutosaveScreenState();
}

class _MoneyBoxAutosaveScreenState extends State<MoneyBoxAutosaveScreen> {
  final _svc = MoneyBoxService();
  int _percent = 5;
  bool _loading = false;

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
      if (ApiService.isPhoneNotVerified(res) ||
          ApiService.isPhoneNotVerified(showMsg)) {
        await showPhoneVerificationRequiredDialog(
          context,
          message: showMsg,
          onRetry: _save,
        );
        return;
      }
      if (ApiService.isTierOrKycRestriction(res) ||
          ApiService.isTierOrKycRestriction(showMsg)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(showMsg),
            action: SnackBarAction(
              label: 'Verify ID',
              onPressed: () {
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const KycScreen()));
              },
            ),
          ),
        );
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
              min: 1,
              max: 30,
              divisions: 29,
              label: '$_percent%',
              onChanged:
                  _loading ? null : (v) => setState(() => _percent = v.round()),
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

