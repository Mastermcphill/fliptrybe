import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_config.dart';
import '../services/receipt_service.dart';

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  final _svc = ReceiptService();
  late Future<List<dynamic>> _future;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _svc.listReceipts();
  }

  void _reload() => setState(() => _future = _svc.listReceipts());

  Future<void> _createDemo() async {
    setState(() => _busy = true);
    final ok = await _svc.createDemoReceipt(kind: 'listing_sale', amount: 10000, reference: 'demo-receipt');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt created (demo)')));
      _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipts'),
        actions: [
          IconButton(
            tooltip: 'Create demo receipt',
            onPressed: _busy ? null : _createDemo,
            icon: const Icon(Icons.receipt_long_outlined),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No receipts yet.')),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final raw = items[i];
                if (raw is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(raw);

                final kind = (m['kind'] ?? '').toString();
                final ref = (m['reference'] ?? '').toString();
                final amount = (m['amount'] ?? 0).toString();
                final fee = (m['fee'] ?? 0).toString();
                final total = (m['total'] ?? 0).toString();
                final when = (m['created_at'] ?? '').toString();

                final id = int.tryParse((m['id'] ?? '').toString()) ?? 0;
                final pdfUrl = id > 0 ? ApiConfig.api('/receipts/$id/pdf') : '';

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_outlined),
                    title: Text(kind, style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text('Ref: $ref\nAmount: NGN $amount | Fee: NGN $fee | Total: NGN $total\n$when'),
                    isThreeLine: true,
                    onTap: () async {
                      if (pdfUrl.isEmpty) return;
                      await Clipboard.setData(ClipboardData(text: pdfUrl));
                      final uri = Uri.tryParse(pdfUrl);
                      if (uri != null) {
                        try {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      }
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('Receipt PDF opened and link copied')));
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
