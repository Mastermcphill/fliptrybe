import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/tokens/ft_spacing.dart';
import '../utils/ft_routes.dart';
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
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Merchant Orders',
      onRefresh: _reload,
      child: FutureBuilder<List<dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return FTSkeletonList(
              itemCount: 4,
              itemBuilder: (_, __) => const FTSkeletonCard(height: 88),
            );
          }
          if (snap.hasError) {
            return FTErrorState(
              message: 'Unable to load merchant orders.',
              onRetry: _reload,
            );
          }
          final items = snap.data ?? const <dynamic>[];
          if (items.isEmpty) {
            return FTEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No merchant orders yet',
              subtitle:
                  'Orders will appear here when buyers check out successfully.',
              primaryCtaText: 'Refresh',
              onPrimaryCta: _reload,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: FTSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: FTSpacing.xs),
            itemBuilder: (context, i) {
              final o = Map<String, dynamic>.from(items[i] as Map);
              final oid = o['id'];
              final id = oid is int ? oid : int.tryParse(oid.toString());
              return FTCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: FTSpacing.xs,
                  vertical: FTSpacing.xxs,
                ),
                child: FTListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  trailing: FTButton(
                    label: 'Timeline',
                    variant: FTButtonVariant.ghost,
                    onPressed: id == null
                        ? null
                        : () {
                            Navigator.of(context).push(
                              FTRoutes.page(
                                child: TransactionTimelineScreen(orderId: id),
                              ),
                            );
                          },
                  ),
                  onTap: () {
                    if (id == null) return;
                    Navigator.of(context).push(
                      FTRoutes.page(
                        child: OrderDetailScreen(orderId: id),
                      ),
                    );
                  },
                  title: 'Order #${o['id']} | NGN ${o['amount']}',
                  subtitle: '${o['status']}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
