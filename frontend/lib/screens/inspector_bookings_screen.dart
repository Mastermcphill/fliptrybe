import 'package:flutter/material.dart';

import '../services/inspector_service.dart';
import 'not_available_yet_screen.dart';
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
  String? _info;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _inspectorService.assignments();
    if (!mounted) return;
    setState(() {
      _info = _inspectorService.lastInfo;
      _items = items
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw as Map))
          .toList();
      _loading = false;
    });
  }

  void _openUnavailable() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NotAvailableYetScreen(
          title: 'Inspection Submission',
          reason:
              'Inspection report submission is not enabled yet for this environment.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Bookings'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(Icons.assignment_outlined, size: 44),
                        const SizedBox(height: 12),
                        Text(
                          (_info ?? 'No assigned inspections yet.').trim(),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                      itemCount: _items.length,
                      itemBuilder: (_, index) {
                        final item = _items[index];
                        final title =
                            (item['listing_title'] ?? 'Inspection').toString();
                        final status =
                            (item['status'] ?? 'assigned').toString();
                        final orderId = (item['order_id'] ?? '-').toString();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            title: Text('$title (Order #$orderId)'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status: $status'),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _openUnavailable,
                                      child: const Text('Submit'),
                                    ),
                                    OutlinedButton(
                                      onPressed: int.tryParse(orderId) == null
                                          ? null
                                          : () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      TransactionTimelineScreen(
                                                    orderId: int.parse(orderId),
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
