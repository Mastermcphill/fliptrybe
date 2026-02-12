import 'dart:math';

import 'package:flutter/material.dart';

import '../services/cart_service.dart';
import '../utils/formatters.dart';
import '../ui/components/ft_components.dart';
import 'manual_payment_instructions_screen.dart';
import 'order_detail_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final CartService _cartService = CartService();

  bool _loading = true;
  bool _checkoutBusy = false;
  String? _error;
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  int _totalMinor = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await _cartService.getCart();
    if (!mounted) return;
    if (data['ok'] != true) {
      setState(() {
        _loading = false;
        _error = (data['message'] ?? 'Unable to load cart').toString();
      });
      return;
    }
    final rows = (data['items'] is List)
        ? (data['items'] as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
    setState(() {
      _items = rows;
      _totalMinor = int.tryParse('${data['total_minor'] ?? 0}') ?? 0;
      _loading = false;
    });
  }

  Future<void> _updateQty(Map<String, dynamic> row, int quantity) async {
    final itemId = int.tryParse('${row['id'] ?? 0}') ?? 0;
    if (itemId <= 0) return;
    if (quantity < 1) quantity = 1;
    final res =
        await _cartService.updateItem(itemId: itemId, quantity: quantity);
    if (res['ok'] != true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                (res['message'] ?? 'Could not update quantity').toString())),
      );
      return;
    }
    await _load();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final itemId = int.tryParse('${row['id'] ?? 0}') ?? 0;
    if (itemId <= 0) return;
    final res = await _cartService.removeItem(itemId);
    if (res['ok'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text((res['message'] ?? 'Could not remove item').toString())),
      );
    }
    await _load();
  }

  Future<void> _checkout() async {
    if (_items.isEmpty || _checkoutBusy) return;
    final method = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Select payment method')),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet'),
              subtitle: const Text('Instant if wallet balance is enough'),
              onTap: () => Navigator.of(context).pop('wallet'),
            ),
            ListTile(
              leading: const Icon(Icons.credit_card_outlined),
              title: const Text('Paystack'),
              subtitle: const Text('Card / bank transfer (automated)'),
              onTap: () => Navigator.of(context).pop('paystack'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Bank Transfer'),
              subtitle: const Text('Manual confirmation with reference'),
              onTap: () => Navigator.of(context).pop('bank_transfer_manual'),
            ),
          ],
        ),
      ),
    );
    if (method == null || method.trim().isEmpty) return;
    setState(() => _checkoutBusy = true);
    final listingIds = _items
        .map((row) => int.tryParse('${row['listing_id'] ?? 0}') ?? 0)
        .where((id) => id > 0)
        .toList(growable: false);
    final idemKey =
        'bulk-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    final res = await _cartService.checkoutBulk(
      listingIds: listingIds,
      paymentMethod: method,
      idempotencyKey: idemKey,
    );
    if (!mounted) return;
    setState(() => _checkoutBusy = false);
    if (res['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text((res['message'] ?? res['error'] ?? 'Checkout failed')
                .toString())),
      );
      return;
    }
    final orderIds = (res['order_ids'] is List)
        ? (res['order_ids'] as List)
            .map((value) => int.tryParse('$value') ?? 0)
            .where((id) => id > 0)
            .toList(growable: false)
        : const <int>[];
    final firstOrderId = orderIds.isNotEmpty ? orderIds.first : 0;
    if (method == 'bank_transfer_manual') {
      final intentId = int.tryParse('${res['payment_intent_id'] ?? 0}');
      final instructions = (res['manual_instructions'] is Map)
          ? Map<String, dynamic>.from(res['manual_instructions'] as Map)
          : const <String, dynamic>{};
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ManualPaymentInstructionsScreen(
            orderId: firstOrderId,
            amount: (res['total'] is num)
                ? (res['total'] as num).toDouble()
                : (_totalMinor / 100.0),
            reference: (res['reference'] ?? '').toString(),
            paymentIntentId: intentId,
            initialInstructions: instructions,
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Checkout started via ${method.replaceAll('_', ' ')}.')),
    );
    if (firstOrderId > 0) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => OrderDetailScreen(orderId: firstOrderId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Cart',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _load)
              : _items.isEmpty
                  ? FTEmptyState(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Your cart is empty',
                      subtitle: 'Add listings to cart before checkout.',
                      actionLabel: 'Refresh',
                      onAction: _load,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, index) {
                              final row = _items[index];
                              final listing = row['listing'] is Map
                                  ? Map<String, dynamic>.from(
                                      row['listing'] as Map)
                                  : <String, dynamic>{};
                              final qty =
                                  int.tryParse('${row['quantity'] ?? 1}') ?? 1;
                              return FTCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (listing['title'] ?? 'Listing')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formatNaira(row['line_total'],
                                          decimals: 0),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        IconButton(
                                          onPressed: () =>
                                              _updateQty(row, qty - 1),
                                          icon: const Icon(
                                              Icons.remove_circle_outline),
                                        ),
                                        Text('$qty'),
                                        IconButton(
                                          onPressed: () =>
                                              _updateQty(row, qty + 1),
                                          icon: const Icon(
                                              Icons.add_circle_outline),
                                        ),
                                        const Spacer(),
                                        TextButton.icon(
                                          onPressed: () => _remove(row),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                          label: const Text('Remove'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          decoration: const BoxDecoration(
                            border: Border(
                                top: BorderSide(color: Color(0xFFE2E8F0))),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Total: ${formatNaira(_totalMinor / 100.0, decimals: 0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _checkoutBusy ? null : _checkout,
                                icon: const Icon(Icons.lock_outline),
                                label: Text(_checkoutBusy
                                    ? 'Processing...'
                                    : 'Checkout'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}
