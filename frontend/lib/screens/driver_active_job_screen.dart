import 'package:flutter/material.dart';

import '../services/driver_directory_service.dart';
import 'order_detail_screen.dart';

class DriverActiveJobScreen extends StatefulWidget {
  const DriverActiveJobScreen({super.key});

  @override
  State<DriverActiveJobScreen> createState() => _DriverActiveJobScreenState();
}

class _DriverActiveJobScreenState extends State<DriverActiveJobScreen> {
  final _svc = DriverDirectoryService();
  bool _loading = true;
  Map<String, dynamic>? _job;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final j = await _svc.activeJob();
    setState(() {
      _job = j;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Active Job'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_job == null)
              ? const Center(child: Text('No active job right now.'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Order #${_job!['id']}",
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text("Status: ${_job!['status'] ?? ''}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          if ((_job!['pickup'] ?? '').toString().isNotEmpty)
                            Text("Pickup: ${_job!['pickup']}"),
                          if ((_job!['dropoff'] ?? '').toString().isNotEmpty)
                            Text("Dropoff: ${_job!['dropoff']}"),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => OrderDetailScreen(
                                              orderId: int.parse(
                                                  _job!['id'].toString()))),
                                    );
                                  },
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('Open Order'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
