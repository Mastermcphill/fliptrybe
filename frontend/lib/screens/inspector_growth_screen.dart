import 'package:flutter/material.dart';

import '../services/inspector_service.dart';

class InspectorGrowthScreen extends StatefulWidget {
  const InspectorGrowthScreen({super.key});

  @override
  State<InspectorGrowthScreen> createState() => _InspectorGrowthScreenState();
}

class _InspectorGrowthScreenState extends State<InspectorGrowthScreen> {
  final _inspectorService = InspectorService();
  bool _loading = true;
  List<dynamic> _assignments = const [];
  String? _info;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final assignments = await _inspectorService.assignments();
      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _info = _inspectorService.lastInfo;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _assignments.length;
    final completed = _assignments.whereType<Map>().where((a) {
      final status = (a['status'] ?? '').toString().toLowerCase();
      return status == 'completed' || status == 'submitted';
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inspector Growth'),
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
                        Text('Assigned Bookings: $total'),
                        Text('Submitted Reports: $completed'),
                        if ((_info ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Info: $_info'),
                        ],
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
                        Text('Progress Plan',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 8),
                        Text(
                            'Increase accepted inspections and keep high report quality.'),
                        Text(
                            'Lower dispute rates improve future booking priority.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
