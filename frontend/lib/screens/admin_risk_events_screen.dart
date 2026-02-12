import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';

class AdminRiskEventsScreen extends StatefulWidget {
  const AdminRiskEventsScreen({super.key});

  @override
  State<AdminRiskEventsScreen> createState() => _AdminRiskEventsScreenState();
}

class _AdminRiskEventsScreenState extends State<AdminRiskEventsScreen> {
  final _qCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  double _minScore = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _qCtrl.text.trim();
      final path =
          '/admin/risk-events?limit=100&min_score=${_minScore.toStringAsFixed(0)}${q.isEmpty ? '' : '&q=${Uri.encodeQueryComponent(q)}'}';
      final data = await ApiClient.instance.getJson(ApiConfig.api(path));
      if (!mounted) return;
      final rows = (data is Map && data['items'] is List) ? data['items'] as List : <dynamic>[];
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load risk events: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Admin Risk Events',
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: _items.isEmpty,
        loadingState: const Center(child: CircularProgressIndicator()),
        emptyState: const FTEmptyState(
          icon: Icons.security_outlined,
          title: 'No risk events',
          subtitle: 'No events match the current risk filters.',
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _qCtrl,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: 'Search action/reason/request id',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Min score'),
                      Expanded(
                        child: Slider(
                          value: _minScore,
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: _minScore.toStringAsFixed(0),
                          onChanged: (value) => setState(() => _minScore = value),
                          onChangeEnd: (_) => _load(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final row = _items[index];
                  return FTCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['action']} • score ${(row['score'] ?? 0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text('Decision: ${(row['decision'] ?? '').toString()}'),
                        Text('Reason: ${(row['reason_code'] ?? '').toString()}'),
                        Text('Request: ${(row['request_id'] ?? '').toString()}'),
                        const SizedBox(height: 4),
                        Text(
                          (row['created_at'] ?? '').toString(),
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
