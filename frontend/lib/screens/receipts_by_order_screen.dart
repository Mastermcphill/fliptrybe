import 'package:flutter/material.dart';

import '../services/receipt_service.dart';

class ReceiptsByOrderScreen extends StatefulWidget {
  final int orderId;
  const ReceiptsByOrderScreen({super.key, required this.orderId});

  @override
  State<ReceiptsByOrderScreen> createState() => _ReceiptsByOrderScreenState();
}

class _ReceiptsByOrderScreenState extends State<ReceiptsByOrderScreen> {
  final _svc = ReceiptService();
  late Future<List<dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = _svc.getByReference("order:${widget.orderId}");
  }

  void _reload() {
    setState(() => _items = _svc.getByReference("order:${widget.orderId}"));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Receipts: Order #${widget.orderId}"),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return const Center(
                child: Text(
                    "No receipts yet. They generate on Delivered/Completed."));
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final raw = rows[i];
              if (raw is! Map) return const SizedBox.shrink();
              final m = Map<String, dynamic>.from(raw);
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  title: Text((m['kind'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: Text("Total: ?${m['total'] ?? 0}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      final url = await _svc
                          .getPdfUrl(int.parse((m['id'] ?? 0).toString()));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("PDF URL: $url")));
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
