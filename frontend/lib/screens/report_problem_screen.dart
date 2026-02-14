import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/support_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/ui_feedback.dart';

class ReportProblemScreen extends StatefulWidget {
  const ReportProblemScreen({super.key});

  @override
  State<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends State<ReportProblemScreen> {
  final SupportService _svc = SupportService();
  final TextEditingController _subjectCtrl =
      TextEditingController(text: 'App issue report');
  final TextEditingController _messageCtrl = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _messageCtrl.text = _diagnosticTemplate();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  String _diagnosticTemplate() {
    final rid = ApiClient.instance.lastFailedRequestId ?? 'none';
    return '''
What happened:

Expected result:

Actual result:

Diagnostics:
- app_version: ${ApiConfig.appVersion}
- platform: ${defaultTargetPlatform.name}
- api_host: ${Uri.tryParse(ApiConfig.baseUrl)?.host ?? 'unknown'}
- support_code: $rid
''';
  }

  Future<void> _submit() async {
    if (_loading) return;
    final subject = _subjectCtrl.text.trim();
    final body = _messageCtrl.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      UIFeedback.showErrorSnack(context, 'Subject and message are required.');
      return;
    }

    setState(() => _loading = true);
    final res = await _svc.createTicket(subject: subject, message: body);
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['ok'] == true) {
      UIFeedback.showSuccessSnack(context, 'Support ticket created.');
      Navigator.of(context).pop(true);
      return;
    }

    UIFeedback.showErrorSnack(
      context,
      (res['message'] ?? 'Unable to submit support ticket.').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Report a Problem',
      child: ListView(
        children: [
          FTSection(
            title: 'Issue details',
            subtitle: 'Share what happened and we will investigate quickly.',
            child: Column(
              children: [
                FTTextField(
                  controller: _subjectCtrl,
                  labelText: 'Subject',
                  enabled: !_loading,
                ),
                const SizedBox(height: 10),
                FTTextField(
                  controller: _messageCtrl,
                  labelText: 'Message',
                  enabled: !_loading,
                  minLines: 8,
                  maxLines: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FTAsyncButton(
            label: 'Submit report',
            icon: Icons.bug_report_outlined,
            externalLoading: _loading,
            onPressed: _loading ? null : _submit,
          ),
        ],
      ),
    );
  }
}
