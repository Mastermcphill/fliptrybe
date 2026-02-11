import 'package:flutter/material.dart';

import '../services/driver_service.dart';

class DriverGrowthScreen extends StatefulWidget {
  const DriverGrowthScreen({super.key});

  @override
  State<DriverGrowthScreen> createState() => _DriverGrowthScreenState();
}

class _DriverGrowthScreenState extends State<DriverGrowthScreen> {
  final _driverService = DriverService();
  bool _loading = true;
  List<dynamic> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final jobs = await _driverService.getJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _jobs.length;
    final completed = _jobs.whereType<Map>().where((j) {
      final status = (j['status'] ?? '').toString().toLowerCase();
      return status == 'delivered' || status == 'completed';
    }).length;
    final successRate = total == 0 ? 0 : ((completed / total) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Growth'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Performance Snapshot',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text('Completed Jobs: $completed'),
                        Text('Total Jobs: $total'),
                        Text('Success Rate: $successRate%'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MoneyBox Suggestion',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text(
                            'Tier 2/3 is usually optimal for drivers with regular weekly payouts.'),
                        Text(
                            'Set autosave and avoid early withdraw to reduce penalty impact.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
