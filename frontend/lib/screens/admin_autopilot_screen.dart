import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';
import '../utils/ui_feedback.dart';
import 'admin_manual_payments_screen.dart';
import 'admin_commission_engine_screen.dart';
import 'settings_demo_screen.dart';
import '../utils/auth_navigation.dart';

class AdminAutopilotScreen extends StatefulWidget {
  const AdminAutopilotScreen({super.key, this.service});

  final AdminAutopilotService? service;

  @override
  State<AdminAutopilotScreen> createState() => _AdminAutopilotScreenState();
}

class _AdminAutopilotScreenState extends State<AdminAutopilotScreen> {
  late final AdminAutopilotService _svc;
  final _manualBankNameCtrl = TextEditingController();
  final _manualAccountNumberCtrl = TextEditingController();
  final _manualAccountNameCtrl = TextEditingController();
  final _manualNoteCtrl = TextEditingController();
  final _manualSlaCtrl = TextEditingController(text: '360');
  bool _loading = true;
  bool _enabled = true;
  String _lastRun = "-";
  Map<String, dynamic> _lastTick = const {};
  Map<String, dynamic> _health = const {};
  Map<String, dynamic> _paymentsSettings = const {};

  String _provider = "mock";
  String _mode = "disabled";
  String _paymentsMode = "mock";
  bool _paystackEnabled = false;
  bool _smsEnabled = false;
  bool _waEnabled = false;
  String _searchV2Mode = "off";
  bool _legacyFallback = false;
  bool _otelEnabled = false;
  bool _rateLimitEnabled = true;
  bool _signingOut = false;
  int _windowDays = 30;
  bool _autopilotBusy = false;
  bool _autopilotLoading = true;
  int? _selectedSnapshotId;
  int? _draftPolicyId;
  Map<String, dynamic>? _impactPreview;
  List<Map<String, dynamic>> _snapshots = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _recommendations = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? AdminAutopilotService();
    _load();
  }

  @override
  void dispose() {
    _manualBankNameCtrl.dispose();
    _manualAccountNumberCtrl.dispose();
    _manualAccountNameCtrl.dispose();
    _manualNoteCtrl.dispose();
    _manualSlaCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _svc.status();
    final payMode = await _svc.getPaymentsMode();
    final pay = await _svc.getPaymentsSettings();
    final snapshots = await _svc.listSnapshots(limit: 20);
    int? targetSnapshot = _selectedSnapshotId;
    if (targetSnapshot == null && snapshots.isNotEmpty) {
      targetSnapshot = int.tryParse('${snapshots.first['id'] ?? 0}');
    }
    final recommendationsPayload =
        await _svc.getRecommendations(snapshotId: targetSnapshot);
    final recommendationItems =
        (recommendationsPayload['items'] is List)
            ? (recommendationsPayload['items'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
    final snapshotFromRec = (recommendationsPayload['snapshot'] is Map)
        ? Map<String, dynamic>.from(recommendationsPayload['snapshot'] as Map)
        : <String, dynamic>{};
    if (!mounted) return;
    final settings = Map<String, dynamic>.from(
        (s['settings'] ?? {}) as Map? ?? <String, dynamic>{});
    final integrations = Map<String, dynamic>.from(
        (settings['integrations'] ?? {}) as Map? ?? <String, dynamic>{});
    final featureFlags = Map<String, dynamic>.from(
        (settings['features'] ?? {}) as Map? ?? <String, dynamic>{});
    final health = Map<String, dynamic>.from(
        (settings['integration_health'] ?? {}) as Map? ?? <String, dynamic>{});
    final paySettings = Map<String, dynamic>.from(
        (pay['settings'] ?? {}) as Map? ?? <String, dynamic>{});
    final payModeSettings = Map<String, dynamic>.from(
        (payMode['settings'] ?? {}) as Map? ?? <String, dynamic>{});
    setState(() {
      _enabled = (settings['enabled'] ?? true) == true;
      _lastRun = (settings['last_run_at'] ?? '-')?.toString() ?? '-';
      _provider = (integrations['payments_provider'] ??
              settings['payments_provider'] ??
              "mock")
          .toString();
      _mode = (integrations['integrations_mode'] ??
              settings['integrations_mode'] ??
              "disabled")
          .toString();
      _paymentsMode = (payModeSettings['mode'] ??
              paySettings['mode'] ??
              settings['payments_mode'] ??
              "mock")
          .toString();
      _paystackEnabled = (integrations['paystack_enabled'] ??
              settings['paystack_enabled'] ??
              false) ==
          true;
      _smsEnabled = (integrations['termii_enabled_sms'] ??
              settings['termii_enabled_sms'] ??
              false) ==
          true;
      _waEnabled = (integrations['termii_enabled_wa'] ??
              settings['termii_enabled_wa'] ??
              false) ==
          true;
      _searchV2Mode = (featureFlags['search_v2_mode'] ??
              settings['search_v2_mode'] ??
              'off')
          .toString();
      _legacyFallback = (featureFlags['payments_allow_legacy_fallback'] ??
              settings['payments_allow_legacy_fallback'] ??
              false) ==
          true;
      _otelEnabled =
          (featureFlags['otel_enabled'] ?? settings['otel_enabled'] ?? false) ==
              true;
      _rateLimitEnabled = (featureFlags['rate_limit_enabled'] ??
              settings['rate_limit_enabled'] ??
              true) ==
          true;
      _health = health;
      _paymentsSettings = paySettings;
      _manualBankNameCtrl.text =
          (paySettings['manual_payment_bank_name'] ?? '').toString();
      _manualAccountNumberCtrl.text =
          (paySettings['manual_payment_account_number'] ?? '').toString();
      _manualAccountNameCtrl.text =
          (paySettings['manual_payment_account_name'] ?? '').toString();
      _manualNoteCtrl.text =
          (paySettings['manual_payment_note'] ?? '').toString();
      _manualSlaCtrl.text =
          (paySettings['manual_payment_sla_minutes'] ?? 360).toString();
      _snapshots = snapshots;
      _selectedSnapshotId =
          int.tryParse('${snapshotFromRec['id'] ?? targetSnapshot ?? 0}');
      _recommendations = recommendationItems;
      _autopilotLoading = false;
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _loading = true);
    await _svc.toggle(enabled: v);
    await _load();
  }

  Future<void> _tick() async {
    setState(() => _loading = true);
    final r = await _svc.tick();
    if (!mounted) return;
    setState(() {
      _lastTick = r;
      _loading = false;
    });
    await _load();
  }

  Future<void> _refreshAutopilotPanel({int? snapshotId}) async {
    setState(() => _autopilotLoading = true);
    final snapshots = await _svc.listSnapshots(limit: 20);
    int? target = snapshotId ?? _selectedSnapshotId;
    if (target == null && snapshots.isNotEmpty) {
      target = int.tryParse('${snapshots.first['id'] ?? 0}');
    }
    final recPayload = await _svc.getRecommendations(snapshotId: target);
    final recItems = (recPayload['items'] is List)
        ? (recPayload['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final selected = (recPayload['snapshot'] is Map)
        ? int.tryParse('${(recPayload['snapshot'] as Map)['id'] ?? target ?? 0}')
        : target;
    if (!mounted) return;
    setState(() {
      _snapshots = snapshots;
      _selectedSnapshotId = selected;
      _recommendations = recItems;
      _autopilotLoading = false;
    });
  }

  Future<void> _runAutopilot() async {
    if (_autopilotBusy) return;
    setState(() {
      _autopilotBusy = true;
      _autopilotLoading = true;
    });
    try {
      final res = await _svc.runAutopilot(window: _windowDays);
      if (!mounted) return;
      final snapshot = (res['snapshot'] is Map)
          ? Map<String, dynamic>.from(res['snapshot'] as Map)
          : <String, dynamic>{};
      final snapId = int.tryParse('${snapshot['id'] ?? 0}');
      UIFeedback.showSuccessSnack(
        context,
        res['idempotent'] == true
            ? 'Autopilot run reused existing snapshot.'
            : 'Autopilot run completed.',
      );
      await _refreshAutopilotPanel(snapshotId: snapId);
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _autopilotBusy = false);
      }
    }
  }

  Future<void> _setRecommendationStatus({
    required int recommendationId,
    required String status,
  }) async {
    if (_autopilotBusy) return;
    setState(() => _autopilotBusy = true);
    try {
      final res = await _svc.updateRecommendationStatus(
        recommendationId: recommendationId,
        status: status,
      );
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() {
          _recommendations = _recommendations.map((row) {
            if (int.tryParse('${row['id'] ?? 0}') == recommendationId) {
              final updated = Map<String, dynamic>.from(row);
              updated['status'] = status;
              return updated;
            }
            return row;
          }).toList(growable: false);
        });
      } else {
        UIFeedback.showErrorSnack(
            context, (res['message'] ?? 'Failed to update status').toString());
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _autopilotBusy = false);
      }
    }
  }

  Future<void> _generateDraftPolicy() async {
    if (_autopilotBusy) return;
    setState(() => _autopilotBusy = true);
    try {
      final res = await _svc.generateDraft(window: _windowDays, acceptedOnly: true);
      if (!mounted) return;
      if (res['ok'] == true && res['policy'] is Map) {
        final policy = Map<String, dynamic>.from(res['policy'] as Map);
        final draftPolicyId = int.tryParse('${policy['id'] ?? 0}');
        setState(() => _draftPolicyId = draftPolicyId);
        UIFeedback.showSuccessSnack(
          context,
          res['idempotent'] == true
              ? 'Existing autopilot draft reused.'
              : 'Autopilot draft policy generated.',
        );
        await _refreshAutopilotPanel(snapshotId: _selectedSnapshotId);
      } else {
        UIFeedback.showErrorSnack(
            context, (res['message'] ?? 'Failed to generate draft').toString());
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _autopilotBusy = false);
      }
    }
  }

  Future<void> _previewImpact() async {
    int? policyId = _draftPolicyId;
    if (policyId == null || policyId <= 0) {
      for (final row in _snapshots) {
        final id = int.tryParse('${row['id'] ?? 0}');
        if (id != null && id == _selectedSnapshotId) {
          policyId = int.tryParse('${row['draft_policy_id'] ?? 0}');
          break;
        }
      }
    }
    if (policyId == null || policyId <= 0) {
      UIFeedback.showErrorSnack(
          context, 'Generate a draft policy before previewing impact.');
      return;
    }
    setState(() => _autopilotBusy = true);
    try {
      final res = await _svc.previewImpact(draftPolicyId: policyId);
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() {
          _impactPreview = res;
          _draftPolicyId = policyId;
        });
      } else {
        UIFeedback.showErrorSnack(
            context, (res['message'] ?? 'Preview failed').toString());
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _autopilotBusy = false);
      }
    }
  }

  Future<void> _openCommissionEngine() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminCommissionEngineScreen()),
    );
  }

  Future<void> _saveIntegrationSettings() async {
    setState(() => _loading = true);
    final r = await _svc.updateSettings(
      paymentsProvider: _provider,
      integrationsMode: _mode,
      paystackEnabled: _paystackEnabled,
      termiiEnabledSms: _smsEnabled,
      termiiEnabledWa: _waEnabled,
      searchV2Mode: _searchV2Mode,
      paymentsAllowLegacyFallback: _legacyFallback,
      otelEnabled: _otelEnabled,
      rateLimitEnabled: _rateLimitEnabled,
    );
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? 'Integration settings updated'
              : (r['message'] ?? 'Failed to update settings').toString())),
    );
    await _load();
  }

  Future<void> _savePaymentsMode() async {
    setState(() => _loading = true);
    final r = await _svc.setPaymentsMode(mode: _paymentsMode);
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? 'Payments mode updated'
              : (r['message'] ?? 'Failed to update payments mode').toString())),
    );
    await _load();
  }

  Future<void> _saveManualPaymentSettings() async {
    final parsedSla = int.tryParse(_manualSlaCtrl.text.trim()) ?? 360;
    setState(() => _loading = true);
    final r = await _svc.savePaymentsSettings(
      mode: _paymentsMode,
      manualPaymentBankName: _manualBankNameCtrl.text.trim(),
      manualPaymentAccountNumber: _manualAccountNumberCtrl.text.trim(),
      manualPaymentAccountName: _manualAccountNameCtrl.text.trim(),
      manualPaymentNote: _manualNoteCtrl.text.trim(),
      manualPaymentSlaMinutes: parsedSla,
    );
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ok
              ? 'Manual payment settings updated'
              : (r['message'] ?? 'Failed to update manual payment settings')
                  .toString())),
    );
    await _load();
  }

  Future<void> _openAppearance() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsDemoScreen()),
    );
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    await logoutToLanding(context);
    if (!mounted) return;
    setState(() => _signingOut = false);
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
              width: 140,
              child:
                  Text(k, style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _healthCard(String title, Map<String, dynamic> payload) {
    final status = (payload['status'] ?? 'unknown').toString();
    final missingRaw = payload['missing'];
    final missing = missingRaw is List
        ? missingRaw.map((e) => e.toString()).toList()
        : <String>[];
    return FTCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('Status: $status'),
            if (missing.isNotEmpty) Text('Missing: ${missing.join(", ")}'),
          ],
        ),
      ),
    );
  }

  Widget _recommendationCard(Map<String, dynamic> row) {
    final recommendation = (row['recommendation'] is Map)
        ? Map<String, dynamic>.from(row['recommendation'] as Map)
        : <String, dynamic>{};
    final riskFlags = (recommendation['risk_flags'] is List)
        ? (recommendation['risk_flags'] as List)
            .map((e) => '$e')
            .toList(growable: false)
        : const <String>[];
    final explanation = (recommendation['explanation'] is List)
        ? (recommendation['explanation'] as List)
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];
    final impact = (recommendation['expected_impact'] is Map)
        ? Map<String, dynamic>.from(recommendation['expected_impact'] as Map)
        : <String, dynamic>{};
    final revenueDelta = int.tryParse('${impact['revenue_delta_minor'] ?? 0}') ?? 0;
    final gmvDelta = int.tryParse('${impact['gmv_delta_minor'] ?? 0}') ?? 0;
    final recommendationId = int.tryParse('${row['id'] ?? 0}') ?? 0;
    final status = (row['status'] ?? 'new').toString();

    return AutopilotRecommendationCard(
      title: (recommendation['title'] ?? 'Recommendation').toString(),
      confidence: (recommendation['confidence'] ?? 'low').toString(),
      status: status,
      riskFlags: riskFlags,
      explanation: explanation,
      revenueDeltaMinor: revenueDelta,
      gmvDeltaMinor: gmvDelta,
      onAccept: _autopilotBusy
          ? null
          : () => _setRecommendationStatus(
              recommendationId: recommendationId,
              status: 'accepted',
            ),
      onDismiss: _autopilotBusy
          ? null
          : () => _setRecommendationStatus(
              recommendationId: recommendationId,
              status: 'dismissed',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final paymentsHealth = Map<String, dynamic>.from(
        (_health['payments'] ?? {}) as Map? ?? <String, dynamic>{});
    final messagingHealth = Map<String, dynamic>.from(
        (_health['messaging'] ?? {}) as Map? ?? <String, dynamic>{});
    final paymentsHealthSignals = Map<String, dynamic>.from(
        (_paymentsSettings['health'] ?? {}) as Map? ?? <String, dynamic>{});
    final paymentsAudit = Map<String, dynamic>.from(
        (_paymentsSettings['audit'] ?? {}) as Map? ?? <String, dynamic>{});
    final missingKeys = (paymentsHealthSignals['missing_keys'] is List)
        ? (paymentsHealthSignals['missing_keys'] as List)
            .map((e) => '$e')
            .toList()
        : <String>[];
    Map<String, dynamic> selectedSnapshot = const <String, dynamic>{};
    for (final row in _snapshots) {
      final id = int.tryParse('${row['id'] ?? 0}');
      if (id != null && id == _selectedSnapshotId) {
        selectedSnapshot = row;
        break;
      }
    }
    final selectedDraftPolicyId =
        int.tryParse('${selectedSnapshot['draft_policy_id'] ?? _draftPolicyId ?? 0}') ?? 0;
    return AdminScaffold(
      title: 'Admin: Autopilot',
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: _enabled,
                  onChanged: _toggle,
                  title: const Text("Autopilot enabled"),
                  subtitle: Text("Last run: $_lastRun"),
                ),
                const SizedBox(height: 8),
                FTCard(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Payments Control Panel",
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _paymentsMode,
                          items: const [
                            DropdownMenuItem(
                                value: "paystack_auto",
                                child: Text("paystack_auto")),
                            DropdownMenuItem(
                                value: "manual_company_account",
                                child: Text("manual_company_account")),
                            DropdownMenuItem(
                                value: "mock", child: Text("mock")),
                          ],
                          decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: "Payments mode"),
                          onChanged: (v) =>
                              setState(() => _paymentsMode = (v ?? "mock")),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _savePaymentsMode,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text("Save payments mode"),
                        ),
                        const SizedBox(height: 8),
                        if (_paymentsMode == "manual_company_account")
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppTokens.s12),
                            decoration: BoxDecoration(
                              color: scheme.tertiaryContainer,
                              border: Border.all(color: scheme.tertiary),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                                "Manual payment enabled. Paystack is bypassed and admin must mark orders as paid."),
                          ),
                        const SizedBox(height: 10),
                        const Text("Manual Payment Account Details",
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        FTInput(
                          controller: _manualBankNameCtrl,
                          label: "Bank name",
                        ),
                        const SizedBox(height: 8),
                        FTInput(
                          controller: _manualAccountNumberCtrl,
                          label: "Account number",
                        ),
                        const SizedBox(height: 8),
                        FTInput(
                          controller: _manualAccountNameCtrl,
                          label: "Account name",
                        ),
                        const SizedBox(height: 8),
                        FTInput(
                          controller: _manualNoteCtrl,
                          minLines: 2,
                          maxLines: 4,
                          label: "Manual payment note",
                        ),
                        const SizedBox(height: 8),
                        FTInput(
                          controller: _manualSlaCtrl,
                          keyboardType: TextInputType.number,
                          label: "Manual payment SLA (minutes)",
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saveManualPaymentSettings,
                          icon: const Icon(Icons.save_as_outlined),
                          label: const Text("Save manual payment details"),
                        ),
                        const SizedBox(height: 8),
                        Text(
                            "Paystack key present: ${paymentsHealthSignals['paystack_secret_present'] == true}"),
                        Text(
                            "Paystack public key present: ${paymentsHealthSignals['paystack_public_present'] == true}"),
                        Text(
                            "Webhook secret present: ${paymentsHealthSignals['paystack_webhook_secret_present'] == true}"),
                        Text(
                            "Last webhook processed: ${(paymentsHealthSignals['last_paystack_webhook_at'] ?? 'none').toString()}"),
                        if (missingKeys.isNotEmpty)
                          Text("Missing keys: ${missingKeys.join(', ')}"),
                        Text(
                            "Last mode change: ${(paymentsAudit['last_changed_at'] ?? 'unknown').toString()}"),
                        Text(
                            "Changed by: ${(paymentsAudit['last_changed_by_email'] ?? paymentsAudit['last_changed_by'] ?? 'unknown').toString()}"),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const AdminManualPaymentsScreen()),
                            );
                          },
                          icon: const Icon(Icons.account_balance_outlined),
                          label: const Text("Open manual payments queue"),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text("Integrations",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _provider,
                  items: const [
                    DropdownMenuItem(value: "mock", child: Text("mock")),
                    DropdownMenuItem(
                        value: "paystack", child: Text("paystack")),
                  ],
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Payments provider"),
                  onChanged: (v) => setState(() => _provider = (v ?? "mock")),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(
                        value: "disabled", child: Text("disabled")),
                    DropdownMenuItem(value: "sandbox", child: Text("sandbox")),
                    DropdownMenuItem(value: "live", child: Text("live")),
                  ],
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Integrations mode"),
                  onChanged: (v) => setState(() => _mode = (v ?? "disabled")),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _paystackEnabled,
                  title: const Text("Payments enabled"),
                  subtitle:
                      const Text("Blocks/permits /api/payments/initialize"),
                  onChanged: (v) => setState(() => _paystackEnabled = v),
                ),
                SwitchListTile(
                  value: _smsEnabled,
                  title: const Text("Termii SMS enabled"),
                  onChanged: (v) => setState(() => _smsEnabled = v),
                ),
                SwitchListTile(
                  value: _waEnabled,
                  title: const Text("Termii WhatsApp enabled"),
                  onChanged: (v) => setState(() => _waEnabled = v),
                ),
                DropdownButtonFormField<String>(
                  value: _searchV2Mode,
                  items: const [
                    DropdownMenuItem(
                        value: "off", child: Text("search_v2 off")),
                    DropdownMenuItem(
                        value: "shadow", child: Text("search_v2 shadow")),
                    DropdownMenuItem(value: "on", child: Text("search_v2 on")),
                  ],
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Search V2 mode"),
                  onChanged: (v) =>
                      setState(() => _searchV2Mode = (v ?? "off")),
                ),
                SwitchListTile(
                  value: _legacyFallback,
                  title: const Text("Allow legacy webhook fallback"),
                  subtitle: const Text(
                      "Enable legacy metadata credit path when intent is missing"),
                  onChanged: (v) => setState(() => _legacyFallback = v),
                ),
                SwitchListTile(
                  value: _otelEnabled,
                  title: const Text("OpenTelemetry enabled"),
                  onChanged: (v) => setState(() => _otelEnabled = v),
                ),
                SwitchListTile(
                  value: _rateLimitEnabled,
                  title: const Text("Rate limiting enabled"),
                  onChanged: (v) => setState(() => _rateLimitEnabled = v),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _saveIntegrationSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text("Save integration settings"),
                ),
                const SizedBox(height: 12),
                _healthCard("Payments health", paymentsHealth),
                _healthCard("Messaging health", messagingHealth),
                const SizedBox(height: 16),
                FTSectionContainer(
                  title: 'Commission Autopilot',
                  subtitle:
                      'Deterministic recommendations only. Policy activation remains manual.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _windowDays,
                        decoration: const InputDecoration(
                          labelText: 'Analysis window',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                          DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                          DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _windowDays = v);
                        },
                      ),
                      const SizedBox(height: 10),
                      FTAsyncButton(
                        label: _autopilotBusy ? 'Running...' : 'Run Autopilot',
                        icon: Icons.auto_graph_outlined,
                        externalLoading: _autopilotBusy,
                        onPressed: _runAutopilot,
                        expand: true,
                      ),
                      const SizedBox(height: 10),
                      if (_snapshots.isNotEmpty)
                        DropdownButtonFormField<int>(
                          initialValue: _selectedSnapshotId,
                          decoration: const InputDecoration(
                            labelText: 'Snapshot',
                            border: OutlineInputBorder(),
                          ),
                          items: _snapshots.map((row) {
                            final id = int.tryParse('${row['id'] ?? 0}') ?? 0;
                            final window = int.tryParse('${row['window_days'] ?? 0}') ?? 0;
                            final recCount =
                                int.tryParse('${row['recommendations_count'] ?? 0}') ?? 0;
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text('Snapshot #$id ($window d, $recCount recs)'),
                            );
                          }).toList(growable: false),
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _selectedSnapshotId = v);
                            await _refreshAutopilotPanel(snapshotId: v);
                          },
                        ),
                      const SizedBox(height: 10),
                      if (_autopilotLoading)
                        Column(
                          children: const [
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: FTSkeletonCard(height: 116),
                            ),
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: FTSkeletonCard(height: 116),
                            ),
                            FTSkeletonCard(height: 116),
                          ],
                        )
                      else if (_recommendations.isEmpty)
                        FTEmptyState(
                          icon: Icons.insights_outlined,
                          title: 'No recommendations yet',
                          subtitle:
                              'Run autopilot to generate draft-safe commission recommendations.',
                          primaryCtaText: 'Run now',
                          onPrimaryCta: _runAutopilot,
                        )
                      else
                        ..._recommendations.map(
                          (row) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _recommendationCard(row),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FTButton(
                        label: 'Generate Draft Policy',
                        icon: Icons.auto_fix_high_outlined,
                        variant: FTButtonVariant.secondary,
                        onPressed: _autopilotBusy ? null : _generateDraftPolicy,
                        expand: true,
                      ),
                      const SizedBox(height: 8),
                      FTButton(
                        label: 'Preview Impact',
                        icon: Icons.analytics_outlined,
                        variant: FTButtonVariant.ghost,
                        onPressed: (_autopilotBusy || selectedDraftPolicyId <= 0)
                            ? null
                            : _previewImpact,
                        expand: true,
                      ),
                      const SizedBox(height: 8),
                      FTButton(
                        label: 'Open Draft in Commission Engine',
                        icon: Icons.open_in_new,
                        variant: FTButtonVariant.ghost,
                        onPressed: _openCommissionEngine,
                        expand: true,
                      ),
                      if (_impactPreview != null) ...[
                        const SizedBox(height: 10),
                        FTCard(
                          child: Padding(
                            padding: const EdgeInsets.all(AppTokens.s12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Projected Revenue Delta: ${(_impactPreview?['projected_revenue_delta_minor'] ?? 0)} minor',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Projected GMV Delta: ${(_impactPreview?['projected_gmv_delta_minor'] ?? 0)} minor',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Liquidity Δ Min Cash: ${((_impactPreview?['liquidity_effect'] is Map ? (_impactPreview?['liquidity_effect']['delta_min_cash_minor'] ?? 0) : 0)).toString()} minor',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _tick,
                  icon: const Icon(Icons.bolt),
                  label: const Text("Run manual tick"),
                ),
                const SizedBox(height: 16),
                const Text("Last tick result",
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_lastTick.isEmpty) const Text("No tick run yet."),
                if (_lastTick.isNotEmpty) ...[
                  _kv("Skipped", (_lastTick['skipped'] ?? '').toString()),
                  _kv("Payouts", (_lastTick['payouts'] ?? '').toString()),
                  _kv("Queue", (_lastTick['queue'] ?? '').toString()),
                  _kv("Drivers", (_lastTick['drivers'] ?? '').toString()),
                ],
                const SizedBox(height: 16),
                FTSectionContainer(
                  title: 'Appearance',
                  subtitle: 'Theme mode and background palette',
                  child: FTButton(
                    label: 'Open appearance settings',
                    icon: Icons.palette_outlined,
                    variant: FTButtonVariant.secondary,
                    onPressed: _openAppearance,
                    expand: true,
                  ),
                ),
                const SizedBox(height: 16),
                FTButton(
                  label: _signingOut ? 'Signing out...' : 'Sign out',
                  icon: Icons.logout,
                  variant: FTButtonVariant.destructive,
                  onPressed: _signingOut ? null : _signOut,
                  expand: true,
                ),
              ],
            ),
    );
  }
}

class AutopilotRecommendationCard extends StatelessWidget {
  const AutopilotRecommendationCard({
    super.key,
    required this.title,
    required this.status,
    required this.confidence,
    required this.riskFlags,
    required this.explanation,
    required this.revenueDeltaMinor,
    required this.gmvDeltaMinor,
    required this.onAccept,
    required this.onDismiss,
  });

  final String title;
  final String status;
  final String confidence;
  final List<String> riskFlags;
  final List<String> explanation;
  final int revenueDeltaMinor;
  final int gmvDeltaMinor;
  final VoidCallback? onAccept;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return FTCard(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FTResponsiveTitleAction(
              title: title,
              subtitle: 'Confidence: $confidence • Status: $status',
            ),
            if (riskFlags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: riskFlags
                    .map((flag) => FTPill(text: flag))
                    .toList(growable: false),
              ),
            ],
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...explanation
                  .take(3)
                  .map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $line'),
                      )),
            ],
            const SizedBox(height: 8),
            Text('Expected revenue Δ: $revenueDeltaMinor minor'),
            Text('Expected GMV Δ: $gmvDeltaMinor minor'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FTButton(
                    label: 'Accept',
                    icon: Icons.check_circle_outline,
                    variant: status == 'accepted'
                        ? FTButtonVariant.primary
                        : FTButtonVariant.secondary,
                    onPressed: onAccept,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FTButton(
                    label: 'Dismiss',
                    icon: Icons.do_not_disturb_alt_outlined,
                    variant: status == 'dismissed'
                        ? FTButtonVariant.destructive
                        : FTButtonVariant.ghost,
                    onPressed: onDismiss,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
