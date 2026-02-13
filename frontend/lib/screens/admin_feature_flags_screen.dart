import 'package:flutter/material.dart';

import '../services/admin_ops_service.dart';
import '../ui/admin/admin_scaffold.dart';
import '../ui/components/ft_components.dart';

class AdminFeatureFlagsScreen extends StatefulWidget {
  const AdminFeatureFlagsScreen({super.key});

  @override
  State<AdminFeatureFlagsScreen> createState() =>
      _AdminFeatureFlagsScreenState();
}

class _AdminFeatureFlagsScreenState extends State<AdminFeatureFlagsScreen> {
  final _svc = AdminOpsService();

  static const _flagDocs = <String, Map<String, dynamic>>{
    'payments.paystack_enabled': {
      'label': 'Paystack Payments',
      'description': 'Enable or disable Paystack payment rail.',
      'danger': true,
    },
    'notifications.termii_enabled': {
      'label': 'Termii Messaging',
      'description': 'Enable SMS and WhatsApp outbound delivery.',
      'danger': false,
    },
    'media.cloudinary_enabled': {
      'label': 'Cloudinary Media',
      'description': 'Enable signed media uploads and Cloudinary URLs.',
      'danger': false,
    },
    'jobs.autopilot_enabled': {
      'label': 'Autopilot Jobs',
      'description': 'Enable background automation ticks.',
      'danger': true,
    },
    'jobs.escrow_runner_enabled': {
      'label': 'Escrow Runner',
      'description': 'Enable settlement processing automation.',
      'danger': true,
    },
    'features.moneybox_enabled': {
      'label': 'MoneyBox Features',
      'description': 'Enable MoneyBox APIs and autosave flows.',
      'danger': true,
    },
  };

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, bool> _flags = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await _svc.getFlags();
      final raw = payload['flags'];
      final next = <String, bool>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          next['$key'] = value == true;
        });
      }
      for (final key in _flagDocs.keys) {
        next.putIfAbsent(key, () => false);
      }
      if (!mounted) return;
      setState(() {
        _flags = next;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load feature flags.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final payload = await _svc.updateFlags(_flags);
      final ok = payload['ok'] == true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              ok ? 'Feature flags updated.' : 'Feature flag update failed.'),
        ),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Feature flag update failed.')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Feature Flags',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _flags.isEmpty,
        loadingState: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            FTListCardSkeleton(withImage: false),
            SizedBox(height: 10),
            FTListCardSkeleton(withImage: false),
            SizedBox(height: 10),
            FTListCardSkeleton(withImage: false),
          ],
        ),
        emptyState: FTEmptyState(
          icon: Icons.toggle_on_outlined,
          title: 'No flags available',
          subtitle: 'Refresh to fetch runtime flags from the backend.',
          actionLabel: 'Refresh',
          onAction: _load,
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const FTSectionHeader(
              title: 'Runtime Toggles',
              subtitle:
                  'Changes apply immediately and are audited server-side.',
            ),
            const SizedBox(height: 8),
            ..._flagDocs.entries.map((entry) {
              final key = entry.key;
              final meta = entry.value;
              final danger = meta['danger'] == true;
              return FTCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: SwitchListTile(
                  value: _flags[key] == true,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _flags[key] = value),
                  title: Text((meta['label'] ?? key).toString()),
                  subtitle: Text(
                    '${(meta['description'] ?? '').toString()}${danger ? '  •  Danger zone' : ''}',
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            FTPrimaryButton(
              label: _saving ? 'Saving...' : 'Save Flags',
              icon: Icons.save_outlined,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
