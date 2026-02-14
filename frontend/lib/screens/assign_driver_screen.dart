import 'package:flutter/material.dart';

import '../services/driver_roster_service.dart';
import '../services/order_service.dart';

class AssignDriverScreen extends StatefulWidget {
  final int orderId;
  const AssignDriverScreen({super.key, required this.orderId});

  @override
  State<AssignDriverScreen> createState() => _AssignDriverScreenState();
}

class _AssignDriverScreenState extends State<AssignDriverScreen> {
  final _roster = DriverRosterService();
  final _orders = OrderService();

  late Future<List<dynamic>> _drivers;
  int? _selectedId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _drivers = _roster.listDrivers();
  }

  Future<void> _assign() async {
    if (_selectedId == null) return;
    setState(() => _saving = true);
    final ok = await _orders.assignDriver(widget.orderId, _selectedId!);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? "Driver assigned ✅" : "Assign failed")));
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Assign Driver #${widget.orderId}")),
      body: FutureBuilder<List<dynamic>>(
        future: _drivers,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
                child: Text(
                    "No drivers found.\nCreate a Driver account to enable assignments."));
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final raw = items[i];
                    if (raw is! Map) return const SizedBox.shrink();
                    final m = Map<String, dynamic>.from(raw);
                    final id = int.tryParse((m['id'] ?? '').toString()) ?? 0;

                    return RadioListTile<int>(
                      value: id,
                      groupValue: _selectedId,
                      onChanged: (v) => setState(() => _selectedId = v),
                      title: Text((m['name'] ?? '').toString().isEmpty
                          ? "Driver #$id"
                          : (m['name'] ?? '').toString()),
                      subtitle: Text((m['email'] ?? '').toString()),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _assign,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: Text(_saving ? "Assigning..." : "Assign Driver"),
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}
