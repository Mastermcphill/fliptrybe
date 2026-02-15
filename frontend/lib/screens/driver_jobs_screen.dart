import 'package:flutter/material.dart';

import '../services/driver_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/unavailable_action.dart';
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
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load jobs: $e';
        _loading = false;
      });
    }
  }

  int? _resolveOrderId(Map<String, dynamic> job) {
    final orderVal = job['order_id'] ?? job['id'];
    if (orderVal is int) return orderVal;
    return int.tryParse(orderVal?.toString() ?? '');
  }

  String _statusLabel(String value) {
    final status = value.toLowerCase();
    if (status.contains('picked')) return 'PICKED UP';
    if (status.contains('deliver')) return 'DELIVERED';
    if (status.contains('accept')) return 'ACCEPTED';
    if (status.contains('assign')) return 'ASSIGNED';
    return status.isEmpty ? 'PENDING' : status.toUpperCase();
  }

  Color _statusColor(String value) {
    final status = value.toLowerCase();
    if (status.contains('deliver')) return const Color(0xFF0F766E);
    if (status.contains('picked')) return const Color(0xFF0369A1);
    if (status.contains('accept') || status.contains('assign')) {
      return const Color(0xFF1D4ED8);
    }
    return const Color(0xFF475569);
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Driver Jobs',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: RefreshIndicator(
        onRefresh: _load,
        child: FTLoadStateLayout(
          loading: _loading,
          error: _error,
          onRetry: _load,
          empty: _jobs.isEmpty,
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
          emptyState: const FTEmptyState(
            icon: Icons.local_shipping_outlined,
            title: 'No jobs assigned',
            subtitle:
                'New delivery assignments will appear here once dispatched.',
          ),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: _jobs.length,
            itemBuilder: (_, index) {
              final job = _jobs[index];
              final orderId = _resolveOrderId(job);
              final status = (job['status'] ?? 'pending').toString();
              final pickup = (job['pickup'] ?? '').toString();
              final dropoff = (job['dropoff'] ?? '').toString();
              final fee = job['delivery_fee'] ?? job['fee'] ?? 0;
              final orderLinked = orderId != null;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Job #${job['id'] ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color:
                                  _statusColor(status).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: TextStyle(
                                color: _statusColor(status),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (pickup.isNotEmpty) Text('Pickup: $pickup'),
                      if (dropoff.isNotEmpty) Text('Dropoff: $dropoff'),
                      const SizedBox(height: 4),
                      Text('Payout estimate: ${formatNaira(fee)}'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: !orderLinked
                                ? null
                                : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            OrderDetailScreen(orderId: orderId),
                                      ),
                                    ),
                            child: const Text('View'),
                          ),
                          OutlinedButton(
                            onPressed: !orderLinked
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
                            child: const Text('Timeline'),
                          ),
                          OutlinedButton(
                            onPressed: null,
                            child: const Text('Navigate'),
                          ),
                        ],
                      ),
                      if (!orderLinked)
                        const UnavailableActionHint(
                          reason:
                              'View and Timeline are disabled because this job has no linked order yet.',
                        ),
                      const UnavailableActionHint(
                        reason:
                            'Navigate is disabled because map navigation integration is not enabled yet.',
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
