import 'package:flutter/material.dart';

import '../services/admin_autopilot_service.dart';

class AdminAutopilotScreen extends StatefulWidget {
  const AdminAutopilotScreen({super.key});

  @override
  State<AdminAutopilotScreen> createState() => _AdminAutopilotScreenState();
}

class _AdminAutopilotScreenState extends State<AdminAutopilotScreen> {
  final _svc = AdminAutopilotService();
  bool _loading = true;
  bool _enabled = true;
  String _lastRun = "-";
  Map<String, dynamic> _lastTick = const {};
  Map<String, dynamic> _health = const {};

  String _provider = "mock";
  String _mode = "disabled";
  bool _paystackEnabled = false;
  bool _smsEnabled = false;
  bool _waEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _svc.status();
    if (!mounted) return;
    final settings = Map<String, dynamic>.from((s['settings'] ?? {}) as Map? ?? <String, dynamic>{});
    final integrations = Map<String, dynamic>.from((settings['integrations'] ?? {}) as Map? ?? <String, dynamic>{});
    final health = Map<String, dynamic>.from((settings['integration_health'] ?? {}) as Map? ?? <String, dynamic>{});
    setState(() {
      _enabled = (settings['enabled'] ?? true) == true;
      _lastRun = (settings['last_run_at'] ?? '-')?.toString() ?? '-';
      _provider = (integrations['payments_provider'] ?? settings['payments_provider'] ?? "mock").toString();
      _mode = (integrations['integrations_mode'] ?? settings['integrations_mode'] ?? "disabled").toString();
      _paystackEnabled = (integrations['paystack_enabled'] ?? settings['paystack_enabled'] ?? false) == true;
      _smsEnabled = (integrations['termii_enabled_sms'] ?? settings['termii_enabled_sms'] ?? false) == true;
      _waEnabled = (integrations['termii_enabled_wa'] ?? settings['termii_enabled_wa'] ?? false) == true;
      _health = health;
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

  Future<void> _saveIntegrationSettings() async {
    setState(() => _loading = true);
    final r = await _svc.updateSettings(
      paymentsProvider: _provider,
      integrationsMode: _mode,
      paystackEnabled: _paystackEnabled,
      termiiEnabledSms: _smsEnabled,
      termiiEnabledWa: _waEnabled,
    );
    if (!mounted) return;
    final ok = r['ok'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Integration settings updated' : (r['message'] ?? 'Failed to update settings').toString())),
    );
    await _load();
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w900))),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }

  Widget _healthCard(String title, Map<String, dynamic> payload) {
    final status = (payload['status'] ?? 'unknown').toString();
    final missingRaw = payload['missing'];
    final missing = missingRaw is List ? missingRaw.map((e) => e.toString()).toList() : <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
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

  @override
  Widget build(BuildContext context) {
    final paymentsHealth = Map<String, dynamic>.from((_health['payments'] ?? {}) as Map? ?? <String, dynamic>{});
    final messagingHealth = Map<String, dynamic>.from((_health['messaging'] ?? {}) as Map? ?? <String, dynamic>{});
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin: Autopilot"),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
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
                const Text("Integrations", style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _provider,
                  items: const [
                    DropdownMenuItem(value: "mock", child: Text("mock")),
                    DropdownMenuItem(value: "paystack", child: Text("paystack")),
                  ],
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Payments provider"),
                  onChanged: (v) => setState(() => _provider = (v ?? "mock")),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(value: "disabled", child: Text("disabled")),
                    DropdownMenuItem(value: "sandbox", child: Text("sandbox")),
                    DropdownMenuItem(value: "live", child: Text("live")),
                  ],
                  decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Integrations mode"),
                  onChanged: (v) => setState(() => _mode = (v ?? "disabled")),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _paystackEnabled,
                  title: const Text("Payments enabled"),
                  subtitle: const Text("Blocks/permits /api/payments/initialize"),
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
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _saveIntegrationSettings,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text("Save integration settings"),
                ),
                const SizedBox(height: 12),
                _healthCard("Payments health", paymentsHealth),
                _healthCard("Messaging health", messagingHealth),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _tick,
                  icon: const Icon(Icons.bolt),
                  label: const Text("Run manual tick"),
                ),
                const SizedBox(height: 16),
                const Text("Last tick result", style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                if (_lastTick.isEmpty) const Text("No tick run yet."),
                if (_lastTick.isNotEmpty) ...[
                  _kv("Skipped", (_lastTick['skipped'] ?? '').toString()),
                  _kv("Payouts", (_lastTick['payouts'] ?? '').toString()),
                  _kv("Queue", (_lastTick['queue'] ?? '').toString()),
                  _kv("Drivers", (_lastTick['drivers'] ?? '').toString()),
                ],
              ],
            ),
    );
  }
}

