import 'package:flutter/material.dart';

import '../services/commission_service.dart';

class AdminCommissionRulesScreen extends StatefulWidget {
  const AdminCommissionRulesScreen({super.key});

  @override
  State<AdminCommissionRulesScreen> createState() => _AdminCommissionRulesScreenState();
}

class _AdminCommissionRulesScreenState extends State<AdminCommissionRulesScreen> {
  final _svc = CommissionService();
  final _kind = TextEditingController(text: "listing_sale");
  final _state = TextEditingController();
  final _category = TextEditingController();
  final _rate = TextEditingController(text: "0.05");

  bool _loading = true;
  List<dynamic> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _svc.listRules(
      kind: _kind.text,
      state: _state.text,
      category: _category.text,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final r = double.tryParse(_rate.text.trim()) ?? 0.0;
    final ok = await _svc.upsertRule(
      kind: _kind.text.trim(),
      state: _state.text.trim(),
      category: _category.text.trim(),
      rate: r,
    );
    _toast(ok ? "Saved ✅" : "Save failed");
    _load();
  }

  @override
  void dispose() {
    _kind.dispose();
    _state.dispose();
    _category.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin: Commission Rules"),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(controller: _kind, decoration: const InputDecoration(labelText: "Kind (listing_sale/delivery/withdrawal)", border: OutlineInputBorder())),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _state, decoration: const InputDecoration(labelText: "State (optional)", border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: _category, decoration: const InputDecoration(labelText: "Category (optional)", border: OutlineInputBorder()))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: _rate, decoration: const InputDecoration(labelText: "Rate (e.g. 0.05)", border: OutlineInputBorder())),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.save), label: const Text("Save Rule"))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.search), label: const Text("Filter"))),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_rows.isEmpty)
                    ? const Center(child: Text("No rules yet."))
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final raw = _rows[i];
                          if (raw is! Map) return const SizedBox.shrink();
                          final m = Map<String, dynamic>.from(raw);
                          final id = int.tryParse((m["id"] ?? "").toString()) ?? 0;
                          return Card(
                            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: ListTile(
                              title: Text("${m['kind']}  •  ${(m['state'] ?? '').toString().isEmpty ? 'ALL' : m['state']}  •  ${(m['category'] ?? '').toString().isEmpty ? 'ALL' : m['category']}",
                                  style: const TextStyle(fontWeight: FontWeight.w900)),
                              subtitle: Text("Rate: ${(m['rate'] ?? 0)}"),
                              trailing: IconButton(
                                icon: const Icon(Icons.block),
                                onPressed: () async {
                                  final ok = await _svc.disableRule(id);
                                  _toast(ok ? "Disabled ✅" : "Disable failed");
                                  _load();
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
