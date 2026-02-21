import 'package:flutter/material.dart';

import '../services/order_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/tokens/ft_spacing.dart';
import '../utils/ft_routes.dart';
import 'listing_detail_screen.dart';
import 'order_detail_screen.dart';
import 'transaction/transaction_timeline_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  final OrderService _service = OrderService();
  bool _loading = true;
  List<dynamic> _rows = const [];
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _service.myOrders();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  String _tabStatus() {
    switch (_tabs.index) {
      case 0:
        return 'all';
      case 1:
        return 'pending';
      case 2:
        return 'in_progress';
      case 3:
        return 'completed';
      default:
        return 'all';
    }
  }

  List<Map<String, dynamic>> _filtered() {
    final status = _tabStatus();
    final out = <Map<String, dynamic>>[];
    for (final raw in _rows) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final value = (map['status'] ?? '').toString().toLowerCase();
      if (status == 'all') {
        out.add(map);
      } else if (status == 'pending') {
        if (['created', 'awaiting_merchant', 'accepted'].contains(value)) {
          out.add(map);
        }
      } else if (status == 'in_progress') {
        if (['assigned', 'picked_up', 'delivered'].contains(value)) {
          out.add(map);
        }
      } else if (status == 'completed') {
        if (['completed', 'cancelled'].contains(value)) {
          out.add(map);
        }
      }
    }
    return out;
  }

  void _openReorder(Map<String, dynamic> item) {
    final listingId = int.tryParse((item['listing_id'] ?? '').toString());
    if (listingId == null) return;
    final listing = <String, dynamic>{
      'id': listingId,
      'owner_id': item['merchant_id'],
      'title': item['listing_title'],
      'price': item['amount'],
    };
    Navigator.of(context).push(
      FTRoutes.page(child: ListingDetailScreen(listing: listing)),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered();
    return FTScaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'In Progress'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      child: FTLoadStateLayout(
        loading: _loading,
        error: null,
        onRetry: _load,
        empty: rows.isEmpty,
        loadingState: FTSkeletonList(
          itemCount: 4,
          itemBuilder: (_, __) => const FTSkeletonCard(height: 108),
        ),
        emptyState: FTEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No orders yet',
          subtitle: 'Your completed checkouts will appear here.',
          primaryCtaText: 'Refresh',
          onPrimaryCta: _load,
        ),
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: FTSpacing.lg),
          itemCount: rows.length,
          itemBuilder: (_, index) {
            final item = rows[index];
            final orderId = int.tryParse((item['id'] ?? '').toString()) ?? 0;
            final amount = (item['amount'] ?? 0).toString();
            final status = (item['status'] ?? '').toString();
            final listingTitle =
                (item['listing_title'] ?? 'Listing').toString();
            return FTCard(
              margin: const EdgeInsets.fromLTRB(0, 0, 0, FTSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FTSectionHeader(
                    title: listingTitle,
                    subtitle: 'Status: $status',
                  ),
                  const SizedBox(height: FTSpacing.xs),
                  Text('Amount: NGN $amount'),
                  const SizedBox(height: FTSpacing.xs),
                  Wrap(
                    spacing: FTSpacing.xs,
                    children: [
                      FTButton(
                        label: 'Reorder',
                        variant: FTButtonVariant.ghost,
                        onPressed: () => _openReorder(item),
                      ),
                      FTButton(
                        label: 'Timeline',
                        variant: FTButtonVariant.ghost,
                        onPressed: orderId <= 0
                            ? null
                            : () => Navigator.of(context).push(
                                  FTRoutes.page(
                                    child: TransactionTimelineScreen(
                                      orderId: orderId,
                                    ),
                                  ),
                                ),
                      ),
                      FTButton(
                        label: 'Details',
                        variant: FTButtonVariant.secondary,
                        onPressed: orderId <= 0
                            ? null
                            : () => Navigator.of(context).push(
                                  FTRoutes.page(
                                    child: OrderDetailScreen(orderId: orderId),
                                  ),
                                ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
