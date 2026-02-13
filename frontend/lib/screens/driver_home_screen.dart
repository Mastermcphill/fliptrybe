import 'package:flutter/material.dart';

import '../services/driver_service.dart';
import '../services/moneybox_service.dart';
import '../services/wallet_service.dart';
import '../ui/components/app_components.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import 'driver_jobs_screen.dart';
import 'growth/growth_analytics_screen.dart';
import 'moneybox_dashboard_screen.dart';
import 'not_available_yet_screen.dart';
import 'support_chat_screen.dart';
import '../widgets/how_it_works/role_how_it_works_entry_card.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, this.onSelectTab});

  final ValueChanged<int>? onSelectTab;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final _walletService = WalletService();
  final _moneyboxService = MoneyBoxService();
  final _driverService = DriverService();
  bool _loading = true;
  bool _autosaveSaving = false;
  bool _autosaveEnabled = false;
  int _autosavePercent = 10;
  Map<String, dynamic>? _wallet;
  Map<String, dynamic> _moneybox = const {};
  List<dynamic> _jobs = const [];

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
        _driverService.getJobs(),
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
        _jobs = values[2] as List<dynamic>;
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
    final activeJobs = _jobs.whereType<Map>().where((j) {
      final status = (j['status'] ?? '').toString().toLowerCase();
      return status == 'assigned' ||
          status == 'accepted' ||
          status == 'picked_up';
    }).length;
    final completedJobs = _jobs.whereType<Map>().where((j) {
      final status = (j['status'] ?? '').toString().toLowerCase();
      return status == 'delivered' || status == 'completed';
    }).length;
    final moneyboxLocked = _moneybox['principal_balance'] ?? 0;
    final today = DateTime.now();
    final todayJobs = _jobs.whereType<Map>().where((j) {
      final createdRaw = (j['created_at'] ?? '').toString();
      if (createdRaw.isEmpty) return false;
      try {
        final dt = DateTime.parse(createdRaw).toLocal();
        return dt.year == today.year &&
            dt.month == today.month &&
            dt.day == today.day;
      } catch (_) {
        return false;
      }
    }).length;
    return FTScaffold(
      title: 'Driver Home',
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
                        title: 'Driver Snapshot',
                        subtitle: 'Trips and balance overview',
                      ),
                      const SizedBox(height: 8),
                      Text('Available Balance: ${_money(_wallet?['balance'])}'),
                      Text('MoneyBox Locked: ${_money(moneyboxLocked)}'),
                      Text("Today's Jobs: $todayJobs"),
                      Text('Pending Pickups: $activeJobs'),
                      Text('Completed Deliveries: $completedJobs'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const RoleHowItWorksEntryCard(role: 'driver'),
                const SizedBox(height: 10),
                const FTCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Earnings Rules',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 8),
                      Text(
                          'Driver payout is delivery fee minus 10% platform commission.'),
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
                            const GrowthAnalyticsScreen(role: 'driver'),
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
                            builder: (_) => const DriverJobsScreen()),
                      );
                    }
                  },
                  icon: Icons.local_shipping_outlined,
                  label: 'Go to Jobs',
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
                        builder: (_) => const NotAvailableYetScreen(
                          title: 'Update Availability',
                          reason:
                              'Driver availability updates are not enabled yet in this release.',
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
