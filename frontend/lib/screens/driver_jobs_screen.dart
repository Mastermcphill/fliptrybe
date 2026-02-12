import 'package:flutter/material.dart';

import '../services/driver_service.dart';
import 'order_detail_screen.dart';
import 'transaction/transaction_timeline_screen.dart';

class DriverJobsScreen extends StatefulWidget {
  const DriverJobsScreen({super.key});

  @override
  State<DriverJobsScreen> createState() => _DriverJobsScreenState();
}

class _DriverJobsScreenState extends State<DriverJobsScreen> {
  final DriverService _driverService = DriverService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = const [];

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
      final jobs = await _driverService.getJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load jobs right now.';
        _loading = false;
      });
    }
  }

  int? _resolveOrderId(Map<String, dynamic> job) {
    final orderVal = job['order_id'] ?? job['id'];
    if (orderVal is int) return orderVal;
    return int.tryParse(orderVal?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Jobs'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _jobs.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.local_shipping_outlined, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          (_error ?? 'No assigned jobs yet.').trim(),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: _jobs.length,
                      itemBuilder: (_, index) {
                        final job = _jobs[index];
                        final orderId = _resolveOrderId(job);
                        final status = (job['status'] ?? 'pending').toString();
                        final pickup = (job['pickup'] ?? '').toString();
                        final dropoff = (job['dropoff'] ?? '').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text('Job #${job['id'] ?? '-'}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status: $status'),
                                if (pickup.isNotEmpty) Text('Pickup: $pickup'),
                                if (dropoff.isNotEmpty)
                                  Text('Dropoff: $dropoff'),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      onPressed: orderId == null
                                          ? null
                                          : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      OrderDetailScreen(
                                                    orderId: orderId,
                                                  ),
                                                ),
                                              ),
                                      child: const Text('Open Order'),
                                    ),
                                    TextButton(
                                      onPressed: orderId == null
                                          ? null
                                          : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TransactionTimelineScreen(
                                                    orderId: orderId,
                                                  ),
                                                ),
                                              ),
                                      child: const Text(
                                          'View Transaction Timeline'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
