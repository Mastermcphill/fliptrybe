import 'package:flutter/material.dart';

import '../services/driver_service.dart';

class DriverMapLiteScreen extends StatefulWidget {
  final int jobId;
  const DriverMapLiteScreen({super.key, required this.jobId});

  @override
  State<DriverMapLiteScreen> createState() => _DriverMapLiteScreenState();
}

class _DriverMapLiteScreenState extends State<DriverMapLiteScreen> {
  final _svc = DriverService();
  bool _loading = true;
  Map<String, dynamic>? _job;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final jobs = await _svc.getJobs();
    Map<String, dynamic>? found;
    for (final j in jobs) {
      if (j is Map &&
          int.tryParse((j["id"] ?? "").toString()) == widget.jobId) {
        found = Map<String, dynamic>.from(j);
      }
    }
    if (!mounted) return;
    setState(() {
      _job = found;
      _loading = false;
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _set(String st) async {
    final res = await _svc.updateStatus(jobId: widget.jobId, status: st);
    _toast(res["ok"] == true ? "Updated ✅" : "Failed");
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Driver Route (Job #${widget.jobId})"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_job == null)
              ? const Center(child: Text("Job not found."))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Route Preview",
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              Text("Pickup: ${_job!['pickup'] ?? ''}"),
                              Text("Dropoff: ${_job!['dropoff'] ?? ''}"),
                              const SizedBox(height: 8),
                              Text("Status: ${_job!['status'] ?? ''}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text("Driver Actions",
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton(
                              onPressed: () => _set("picked_up"),
                              child: const Text("Picked Up")),
                          ElevatedButton(
                              onPressed: () => _set("delivered"),
                              child: const Text("Delivered")),
                          ElevatedButton(
                              onPressed: () => _set("completed"),
                              child: const Text("Completed")),
                        ],
                      )
                    ],
                  ),
                ),
    );
  }
}
