import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../services/driver_directory_service.dart';

class DriverJobMapScreen extends StatefulWidget {
  const DriverJobMapScreen({super.key});

  @override
  State<DriverJobMapScreen> createState() => _DriverJobMapScreenState();
}

class _DriverJobMapScreenState extends State<DriverJobMapScreen> {
  final _drivers = DriverDirectoryService();
  final _orders = OrderService();
  bool _loading = true;
  Map<String, dynamic>? _job;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final job = await _drivers.activeJob();
    if (!mounted) return;
    setState(() {
      _job = job;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setStatus(String s) async {
    final id = int.tryParse((_job?['id'] ?? '').toString());
    if (id == null) return;
    if (s == 'delivered') {
      _toast('Buyer must confirm delivery.');
      return;
    }

    String? code;
    if (s == 'picked_up') {
      final ctrl = TextEditingController();
      final okInput = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enter pickup code'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Pickup code', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm')),
          ],
        ),
      );
      if (okInput != true) return;
      code = ctrl.text.trim();
      if (code.isEmpty) {
        _toast('Pickup code required.');
        return;
      }
    }

    final ok = await _orders.driverSetStatus(id, s, code: code);
    _toast(ok ? 'Status updated' : 'Update failed');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver: Active Job'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_job == null)
              ? const Center(child: Text('No active job.'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #${_job!['id']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 18)),
                      const SizedBox(height: 10),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.store_outlined),
                          title: const Text('Pickup'),
                          subtitle: Text((_job!['pickup'] ?? '').toString()),
                        ),
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.home_outlined),
                          title: const Text('Dropoff'),
                          subtitle: Text((_job!['dropoff'] ?? '').toString()),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text('Quick Actions',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        children: [
                          ElevatedButton(
                              onPressed: () => _setStatus('picked_up'),
                              child: const Text('Picked Up')),
                          OutlinedButton(
                              onPressed: () => _setStatus('delivered'),
                              child: const Text('Delivered')),
                          OutlinedButton(
                              onPressed: () => _setStatus('completed'),
                              child: const Text('Complete')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Map preview is stubbed for demo; real maps can be added with Google Maps later.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
    );
  }
}
