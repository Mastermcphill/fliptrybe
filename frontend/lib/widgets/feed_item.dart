import 'package:flutter/material.dart';

import '../screens/listing_detail_screen.dart';
import '../screens/order_detail_screen.dart';
import '../services/order_service.dart';
import 'safe_image.dart';

class FeedItem extends StatelessWidget {
  const FeedItem({super.key, required this.listing});

  final Map<String, dynamic> listing;

  String _s(dynamic v) => (v == null) ? '' : v.toString().trim();

  String? _extractImageUrl(Map<String, dynamic> l) {
    final a = l['image'];
    final b = l['image_path'];

    final s1 = a is String ? a.trim() : '';
    final s2 = b is String ? b.trim() : '';

    if (s1.isNotEmpty) return s1;
    if (s2.isNotEmpty) return s2;
    return null;
  }

  double _price(dynamic v) {
    try {
      if (v is num) return v.toDouble();
      return double.parse(v.toString());
    } catch (_) {
      return 0.0;
    }
  }

  Future<void> _buyNow(BuildContext context) async {
    final svc = OrderService();

    final title = _s(listing['title']);
    final listingId = int.tryParse(_s(listing['id']));
    final merchantId = int.tryParse(_s(listing['user_id'])) ??
        int.tryParse(_s(listing['merchant_id']));

    if (merchantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Can't buy: merchant missing on listing")),
      );
      return;
    }

    final amount = _price(listing['price']);
    final deliveryFee = 500.0;

    final order = await svc.createOrder(
      listingId: listingId,
      merchantId: merchantId,
      amount: amount,
      deliveryFee: deliveryFee,
      pickup: 'Merchant pickup',
      dropoff: 'Customer dropoff',
      paymentReference: '',
    );

    if (order == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order creation failed')),
      );
      return;
    }

    final orderId = int.tryParse(_s(order['id']));
    if (orderId == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Order created ($title)')),
    );

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _s(listing['title']);
    final desc = _s(listing['description']);
    final imageUrl = _extractImageUrl(listing);
    final price = _price(listing['price']);

    final priceText = price <= 0 ? 'NGN 0' : 'NGN ${price.toStringAsFixed(0)}';

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ListingDetailScreen(listing: listing)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              SafeImage(
                url: imageUrl,
                width: 86,
                height: 86,
                borderRadius: BorderRadius.circular(12),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      desc.isEmpty ? 'No description' : desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(priceText,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: () => _buyNow(context),
                          child: const Text('Buy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
