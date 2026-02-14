import 'package:flutter/material.dart';

import '../services/commission_policy_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class AdminCommissionEngineScreen extends StatefulWidget {
  const AdminCommissionEngineScreen({super.key});

  @override
  State<AdminCommissionEngineScreen> createState() =>
      _AdminCommissionEngineScreenState();
}

class _AdminCommissionEngineScreenState
    extends State<AdminCommissionEngineScreen> {
  final _svc = CommissionPolicyService();
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _previewAmountCtrl = TextEditingController(text: '100000');
  final _previewCityCtrl = TextEditingController(text: 'Lagos');

  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _policies = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _preview;
  String _previewAppliesTo = 'declutter';
  String _previewSellerType = 'merchant';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _previewAmountCtrl.dispose();
    _previewCityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _svc.listPolicies();
      if (!mounted) return;
      setState(() {
        _policies = rows;
      });
    } catch (e) {
      if (!mounted) return;
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createDraft() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      UIFeedback.showErrorSnack(context, 'Policy name is required.');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _svc.createDraft(name: name, notes: _notesCtrl.text);
      if (!mounted) return;
      if ((res['ok'] == true) || res.containsKey('policy')) {
        _nameCtrl.clear();
        _notesCtrl.clear();
        UIFeedback.showSuccessSnack(context, 'Draft policy created.');
        await _load();
      } else {
        UIFeedback.showErrorSnack(context, 'Could not create policy.');
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _addQuickRule(int policyId) async {
    setState(() => _saving = true);
    try {
      final res = await _svc.addRule(
        policyId: policyId,
        appliesTo: _previewAppliesTo,
        sellerType: _previewSellerType,
        baseRateBps: 500,
        city: _previewCityCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['rule'] != null) {
        UIFeedback.showSuccessSnack(context, 'Rule added.');
        await _load();
      } else {
        UIFeedback.showErrorSnack(context, 'Could not add rule.');
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _activate(int policyId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await _svc.activate(policyId);
      if (!mounted) return;
      if (res['ok'] == true) {
        UIFeedback.showSuccessSnack(context, 'Policy activated.');
        await _load();
      } else {
        UIFeedback.showErrorSnack(context, 'Could not activate policy.');
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _archive(int policyId) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await _svc.archive(policyId);
      if (!mounted) return;
      if (res['ok'] == true) {
        UIFeedback.showSuccessSnack(context, 'Policy archived.');
        await _load();
      } else {
        UIFeedback.showErrorSnack(context, 'Could not archive policy.');
      }
    } catch (e) {
      if (mounted) {
        UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _previewRule() async {
    final amount = int.tryParse(_previewAmountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      UIFeedback.showErrorSnack(context, 'Enter a valid amount in minor units.');
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _svc.preview(
        appliesTo: _previewAppliesTo,
        sellerType: _previewSellerType,
        city: _previewCityCtrl.text.trim(),
        amountMinor: amount,
      );
      if (!mounted) return;
      setState(() => _preview = res);
    } catch (e) {
      UIFeedback.showErrorSnack(context, UIFeedback.mapDioErrorToMessage(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _policyTile(Map<String, dynamic> row) {
    final id = int.tryParse('${row['id'] ?? 0}') ?? 0;
    final status = (row['status'] ?? 'draft').toString();
    final rules = (row['rules'] is List) ? row['rules'] as List : const [];
    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTResponsiveTitleAction(
            title: (row['name'] ?? 'Policy').toString(),
            subtitle: 'Status: $status • Rules: ${rules.length}',
            action: FTButton(
              label: status == 'active' ? 'Archive' : 'Activate',
              variant: status == 'active'
                  ? FTButtonVariant.ghost
                  : FTButtonVariant.primary,
              onPressed: _saving
                  ? null
                  : () => status == 'active' ? _archive(id) : _activate(id),
            ),
          ),
          if ((row['notes'] ?? '').toString().trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text((row['notes'] ?? '').toString()),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: rules.take(4).map<Widget>((rule) {
              final map = Map<String, dynamic>.from(rule as Map);
              final bps = int.tryParse('${map['base_rate_bps'] ?? 0}') ?? 0;
              return FTPill(
                text:
                    '${map['applies_to']}/${map['seller_type']} @ ${bps / 100}%',
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 10),
          FTButton(
            label: 'Add quick rule',
            icon: Icons.add,
            variant: FTButtonVariant.secondary,
            onPressed: _saving ? null : () => _addQuickRule(id),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Commission Engine',
      actions: [
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ],
      child: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          FTCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FTResponsiveTitleAction(
                  title: 'Create Draft Policy',
                  subtitle:
                      'Policies are explicit and versioned. Activation affects only new transactions.',
                ),
                const SizedBox(height: 10),
                FTInput(controller: _nameCtrl, label: 'Policy name'),
                const SizedBox(height: 10),
                FTInput(controller: _notesCtrl, label: 'Notes (optional)'),
                const SizedBox(height: 10),
                FTButton(
                  label: _saving ? 'Saving...' : 'Create draft',
                  icon: Icons.add_circle_outline,
                  onPressed: _saving ? null : _createDraft,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FTCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FTResponsiveTitleAction(
                  title: 'Preview Calculator',
                  subtitle: 'Simulation only. No ledger writes.',
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _previewAppliesTo,
                  decoration: const InputDecoration(
                    labelText: 'Applies to',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'declutter', child: Text('Declutter')),
                    DropdownMenuItem(value: 'shortlet', child: Text('Shortlet')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _previewAppliesTo = value);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _previewSellerType,
                  decoration: const InputDecoration(
                    labelText: 'Seller type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'merchant', child: Text('Merchant')),
                    DropdownMenuItem(value: 'user', child: Text('User')),
                    DropdownMenuItem(value: 'all', child: Text('All')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _previewSellerType = value);
                  },
                ),
                const SizedBox(height: 10),
                FTInput(
                  controller: _previewCityCtrl,
                  label: 'City',
                ),
                const SizedBox(height: 10),
                FTInput(
                  controller: _previewAmountCtrl,
                  label: 'Amount (minor units)',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                FTButton(
                  label: _saving ? 'Calculating...' : 'Preview commission',
                  icon: Icons.calculate_outlined,
                  onPressed: _saving ? null : _previewRule,
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 12),
                  FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fee: ${formatNaira(((_preview?['commission_fee_minor'] ?? 0) as num).toDouble() / 100)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Policy: ${(_preview?['policy'] is Map ? (_preview?['policy']['policy_name'] ?? 'default') : 'default')}',
                        ),
                        Text(
                          'Effective bps: ${(_preview?['policy'] is Map ? (_preview?['policy']['effective_rate_bps'] ?? 0) : 0)}',
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const FTSkeletonList(
              itemCount: 3,
              itemBuilder: _skeletonPolicyCard,
            )
          else if (_policies.isEmpty)
            FTEmptyState(
              icon: Icons.percent_outlined,
              title: 'No policies yet',
              subtitle: 'Create a draft policy to start tuning commissions safely.',
              primaryCtaText: 'Refresh',
              onPrimaryCta: _load,
            )
          else
            ..._policies
                .map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _policyTile(row),
                  ),
                )
                ,
        ],
      ),
    );
  }
}

Widget _skeletonPolicyCard(BuildContext context, int _) {
  return const Padding(
    padding: EdgeInsets.only(bottom: 10),
    child: FTSkeletonCard(height: 120),
  );
}
