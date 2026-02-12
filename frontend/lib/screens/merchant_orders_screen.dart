import 'package:flutter/material.dart';
import '../services/order_service.dart';
import 'order_detail_screen.dart';
import 'transaction/transaction_timeline_screen.dart';

class MerchantOrdersScreen extends StatefulWidget {
  const MerchantOrdersScreen({super.key});

  @override
  State<MerchantOrdersScreen> createState() => _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends State<MerchantOrdersScreen> {
  final _svc = OrderService();
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _svc.merchantOrders();
  }

  Future<void> _reload() async {
    setState(() => _future = _svc.merchantOrders());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Merchant Orders')),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 50),
                  Icon(Icons.receipt_long_outlined, size: 44),
                  SizedBox(height: 12),
                  Center(child: Text('No merchant orders yet.')),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, i) {
                final o = items[i] as Map<String, dynamic>;
                final oid = o['id'];
                final id = (oid is int) ? oid : int.tryParse(oid.toString());
                return ListTile(
                  leading: const Icon(Icons.storefront),
                  trailing: TextButton(
                    onPressed: id == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TransactionTimelineScreen(orderId: id),
                              ),
                            );
                          },
                    child: const Text('Timeline'),
                  ),
                  onTap: () {
                    if (id != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => OrderDetailScreen(orderId: id)),
                      );
                    }
                  },
                  title: Text('Order #${o['id']} | ?${o['amount']}'),
                  subtitle: Text('${o['status']}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
