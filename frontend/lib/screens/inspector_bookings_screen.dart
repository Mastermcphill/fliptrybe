import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/inspector_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/unavailable_action.dart';
import 'transaction/transaction_timeline_screen.dart';

class InspectorBookingsScreen extends StatefulWidget {
  const InspectorBookingsScreen({super.key});

  @override
  State<InspectorBookingsScreen> createState() =>
      _InspectorBookingsScreenState();
}

class _InspectorBookingsScreenState extends State<InspectorBookingsScreen> {
  final InspectorService _inspectorService = InspectorService();
  bool _loading = true;
  String? _error;
  String? _info;
  List<Map<String, dynamic>> _items = const [];

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
      final items = await _inspectorService.assignments();
      if (!mounted) return;
      setState(() {
        _info = _inspectorService.lastInfo;
        _items = items
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load bookings: $e';
      });
    }
  }

  DateTime _dateOf(Map<String, dynamic> item) {
    final candidates = [
      item['appointment_at'],
      item['scheduled_at'],
      item['created_at'],
    ];
    for (final raw in candidates) {
      final value = (raw ?? '').toString();
      if (value.trim().isEmpty) continue;
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {}
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s.contains('complete') || s.contains('submitted')) return 'COMPLETED';
    if (s.contains('cancel')) return 'CANCELLED';
    if (s.contains('pending') || s.contains('assign')) return 'UPCOMING';
    return s.isEmpty ? 'PENDING' : s.toUpperCase();
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('complete') || s.contains('submitted')) {
      return const Color(0xFF0F766E);
    }
    if (s.contains('cancel')) return const Color(0xFFB91C1C);
    return const Color(0xFF1D4ED8);
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [..._items]
      ..sort((a, b) => _dateOf(a).compareTo(_dateOf(b)));

    return FTScaffold(
      title: 'Inspector Bookings',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: RefreshIndicator(
        onRefresh: _load,
        child: FTLoadStateLayout(
          loading: _loading,
          error: _error,
          onRetry: _load,
          empty: sorted.isEmpty,
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
            icon: Icons.assignment_outlined,
            title: 'No assigned inspections',
            subtitle:
                (_info ?? 'Inspection bookings will appear here when assigned.')
                    .trim(),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: sorted.length,
            itemBuilder: (_, index) {
              final item = sorted[index];
              final dt = _dateOf(item);
              final showHeader = index == 0 ||
                  DateUtils.dateOnly(dt) !=
                      DateUtils.dateOnly(_dateOf(sorted[index - 1]));
              final title = (item['listing_title'] ?? 'Inspection').toString();
              final status = (item['status'] ?? 'assigned').toString();
              final orderId = int.tryParse((item['order_id'] ?? '').toString());
              final hasLinkedOrder = orderId != null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showHeader)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                      child: Text(
                        DateFormat('EEEE, d MMM yyyy').format(dt),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _statusColor(status)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _statusColor(status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text('Order #${orderId?.toString() ?? '-'}'),
                          Text(DateFormat('h:mm a').format(dt)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: null,
                                child: const Text('Submit Report'),
                              ),
                              OutlinedButton(
                                onPressed: !hasLinkedOrder
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                TransactionTimelineScreen(
                                              orderId: orderId,
                                            ),
                                          ),
                                        ),
                                child: const Text('Timeline'),
                              ),
                            ],
                          ),
                          const UnavailableActionHint(
                            reason:
                                'Submit Report is disabled because inspection report submission is not enabled yet for this environment.',
                          ),
                          if (!hasLinkedOrder)
                            const UnavailableActionHint(
                              reason:
                                  'Timeline is disabled because this booking has no linked order ID.',
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
