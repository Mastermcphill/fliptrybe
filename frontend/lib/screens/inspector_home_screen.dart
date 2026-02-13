import 'package:flutter/material.dart';

import '../services/inspector_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import '../ui/components/app_components.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import 'growth/growth_analytics_screen.dart';
import 'inspector_bookings_screen.dart';
import 'moneybox_dashboard_screen.dart';
import 'not_available_yet_screen.dart';
import 'support_chat_screen.dart';
import '../widgets/how_it_works/role_how_it_works_entry_card.dart';

class InspectorHomeScreen extends StatefulWidget {
  const InspectorHomeScreen({super.key, this.onSelectTab});

  final ValueChanged<int>? onSelectTab;

  @override
  State<InspectorHomeScreen> createState() => _InspectorHomeScreenState();
}

class _InspectorHomeScreenState extends State<InspectorHomeScreen> {
  final _walletService = WalletService();
  final _moneyboxService = MoneyBoxService();
  final _inspectorService = InspectorService();
  bool _loading = true;
  bool _autosaveSaving = false;
  bool _autosaveEnabled = false;
  int _autosavePercent = 10;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic> _moneybox = const {};
  List<dynamic> _assignments = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final values = await Future.wait([
        _walletService.getWallet(),
        _moneyboxService.status(),
        _inspectorService.assignments(),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = values[0] as Map<String, dynamic>?;
        _moneybox = values[1] as Map<String, dynamic>;
        _autosaveEnabled = _moneybox['autosave_enabled'] == true;
        final parsedPct =
            int.tryParse('${_moneybox['autosave_percent'] ?? 0}') ?? 0;
        _autosavePercent = parsedPct < 1
            ? 10
            : parsedPct > 30
                ? 30
                : parsedPct;
        _assignments = values[2] as List<dynamic>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _money(dynamic value) => formatNaira(value);

  Future<void> _saveAutosave() async {
    if (_autosaveSaving) return;
    setState(() => _autosaveSaving = true);
    try {
      final res = await _moneyboxService.updateAutosaveSettings(
        enabled: _autosaveEnabled,
        percent: _autosavePercent,
      );
      if (!mounted) return;
      final ok = res['ok'] == true;
      FTToast.show(
        context,
        ok
            ? 'Autosave settings updated.'
            : (res['message'] ?? 'Autosave update failed').toString(),
      );
      if (ok) {
        await _reload();
      }
    } finally {
      if (mounted) setState(() => _autosaveSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _assignments.whereType<Map>().where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'assigned' || status == 'pending';
    }).length;
    final completed = _assignments.whereType<Map>().where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'completed' || status == 'submitted';
    }).length;
    final rating = _assignments.whereType<Map>().fold<double>(0.0, (sum, a) {
      final raw = double.tryParse((a['rating'] ?? 0).toString()) ?? 0;
      return sum + raw;
    });
    final ratedCount = _assignments.whereType<Map>().where((a) {
      final raw = double.tryParse((a['rating'] ?? 0).toString()) ?? 0;
      return raw > 0;
    }).length;
    final avgRating =
        ratedCount == 0 ? '-' : (rating / ratedCount).toStringAsFixed(1);
    return FTScaffold(
      title: 'Inspector Home',
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ],
      child: _loading
          ? ListView(
              children: const [
                FTMetricSkeletonTile(),
                SizedBox(height: 10),
                FTListCardSkeleton(withImage: false),
                SizedBox(height: 10),
                FTListCardSkeleton(withImage: false),
              ],
            )
          : ListView(
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppSectionHeader(
                        title: 'Inspector Snapshot',
                        subtitle: 'Bookings and earnings overview',
                      ),
                      const SizedBox(height: 8),
                      Text('Available Balance: ${_money(_wallet?['balance'])}'),
                      Text(
                          'MoneyBox Locked: ${_money(_moneybox['principal_balance'])}'),
                      Text('Pending Bookings: $pending'),
                      Text('Completed Inspections: $completed'),
                      Text('Rating Snapshot: $avgRating'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const RoleHowItWorksEntryCard(role: 'inspector'),
                const SizedBox(height: 10),
                const FTCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earnings Rules',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text(
                          'Inspection payout is inspection fee minus 10% platform commission.'),
                      Text('Withdraw fee: instant 1%, standard 0%.'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FTCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Autosave Earnings',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _autosaveEnabled,
                        onChanged: (value) =>
                            setState(() => _autosaveEnabled = value),
                        title: const Text('Enable autosave'),
                        subtitle: const Text(
                            'Automatically move part of eligible credits into MoneyBox.'),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _autosavePercent.toDouble(),
                              min: 1,
                              max: 30,
                              divisions: 29,
                              label: '$_autosavePercent%',
                              onChanged: _autosaveEnabled
                                  ? (value) => setState(
                                      () => _autosavePercent = value.round())
                                  : null,
                            ),
                          ),
                          Text('$_autosavePercent%'),
                        ],
                      ),
                      FTPrimaryButton(
                        onPressed: _autosaveSaving ? null : _saveAutosave,
                        icon: Icons.save_outlined,
                        label: _autosaveSaving
                            ? 'Saving...'
                            : 'Save autosave settings',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                FTSecondaryButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const GrowthAnalyticsScreen(role: 'inspector'),
                      ),
                    );
                  },
                  icon: Icons.calculate_outlined,
                  label: 'Estimate Earnings',
                ),
                const SizedBox(height: 8),
                FTSecondaryButton(
                  onPressed: () {
                    if (widget.onSelectTab != null) {
                      widget.onSelectTab!(3);
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const InspectorBookingsScreen()),
                      );
                    }
                  },
                  icon: Icons.assignment_outlined,
                  label: 'View Bookings',
                ),
                const SizedBox(height: 8),
                FTSecondaryButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const NotAvailableYetScreen(
                          title: 'Update Availability',
                          reason:
                              'Inspector availability updates are not enabled yet in this release.',
                        ),
                      ),
                    );
                  },
                  icon: Icons.power_settings_new_outlined,
                  label: 'Update Availability',
                ),
                const SizedBox(height: 8),
                FTSecondaryButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const MoneyBoxDashboardScreen()),
                    );
                  },
                  icon: Icons.savings_outlined,
                  label: 'MoneyBox',
                ),
                const SizedBox(height: 8),
                FTSecondaryButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const SupportChatScreen()),
                    );
                  },
                  icon: Icons.support_agent_outlined,
                  label: 'Chat Admin',
                ),
              ],
            ),
    );
  }
}
