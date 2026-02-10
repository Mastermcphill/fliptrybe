import 'package:flutter/material.dart';
import '../widgets/safe_image.dart';
import '../services/listing_service.dart';
import '../services/order_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../widgets/email_verification_dialog.dart';
import 'order_detail_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  final Map<String, dynamic> listing;

  const ListingDetailScreen({super.key, required this.listing});

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _listings = ListingService();
  final _pickupCtrl = TextEditingController(text: 'Ikeja, Lagos');
  final _dropoffCtrl = TextEditingController(text: 'Lekki, Lagos');
  final _deliveryFeeCtrl = TextEditingController(text: '1500');

  final _orders = OrderService();
  final _auth = AuthService();

  bool _busy = false;
  int? _viewerId;
  Map<String, dynamic> _detail = {};
  bool _detailLoading = false;
  String? _detailError;

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _detail = Map<String, dynamic>.from(widget.listing);
    _loadDetail();
    _loadViewer();
  }

  Future<void> _loadDetail() async {
    final idVal = widget.listing['id'];
    final id = idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
    if (id == null || id <= 0) return;
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final data = await _listings.getListing(id);
      if (data.isNotEmpty) {
        setState(() => _detail = data);
      }
    } catch (e) {
      setState(() => _detailError = e.toString());
    } finally {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  Future<void> _loadViewer() async {
    final profile = await _auth.me();
    if (!mounted) return;
    setState(() {
      final idVal = profile?['id'];
      _viewerId = idVal is int ? idVal : int.tryParse(idVal?.toString() ?? '');
    });
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buyNowAndRequestDelivery() async {
    final merchantId = _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']);
    if (_viewerId != null && merchantId != null && merchantId == _viewerId) {
      _toast("You can't buy your own listing.");
      return;
    }
    setState(() => _busy = true);
    try {
      final listingId = _asInt(_detail['id']);
      final amount = _asDouble(_detail['price']);
      final deliveryFee = _asDouble(_deliveryFeeCtrl.text);

      if (listingId == null || listingId <= 0) {
        throw Exception('Listing not available for purchase yet');
      }
      if (amount <= 0) throw Exception('Invalid price');
      if (merchantId == null || merchantId <= 0) {
        throw Exception('Listing has no merchant (user_id missing)');
      }

      final result = await _orders.createOrderDetailed(
        listingId: listingId,
        merchantId: merchantId,
        amount: amount,
        deliveryFee: deliveryFee,
        pickup: _pickupCtrl.text.trim(),
        dropoff: _dropoffCtrl.text.trim(),
        paymentReference: 'demo',
      );

      if (result['ok'] != true) {
        final msg =
            (result['message'] ?? result['error'] ?? 'Order not created')
                .toString();
        if (ApiService.isEmailNotVerified(result) ||
            ApiService.isEmailNotVerified(msg)) {
          if (!mounted) return;
          await showEmailVerificationRequiredDialog(
            context,
            message: msg,
            onRetry: _buyNowAndRequestDelivery,
          );
          return;
        }
        if (ApiService.isSellerCannotBuyOwnListing(result) ||
            ApiService.isSellerCannotBuyOwnListing(msg)) {
          _toast("You can't place an order on your own listing.");
          return;
        }
        _toast(msg);
        return;
      }

      final orderRaw = result['order'] is Map
          ? Map<String, dynamic>.from(result['order'] as Map)
          : result;
      final order = Map<String, dynamic>.from(orderRaw);
      final orderId = _asInt(order['id']);
      if (orderId == null) throw Exception('Order not created');

      if (!mounted) return;
      _toast('Order created');
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderId)));
    } catch (e) {
      if (mounted) _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (_detail['title'] ?? '').toString();
    final desc = (_detail['description'] ?? '').toString();
    final price = _asDouble(_detail['price']);
    final img = (_detail['image'] ?? _detail['image_path'] ?? '').toString();
    final isDemo = _detail['is_demo'] == true;
    final listingId = _asInt(_detail['id']);
    final merchantId = _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']);
    final isOwnListing =
        _viewerId != null && merchantId != null && merchantId == _viewerId;
    final canBuy = !isOwnListing &&
        listingId != null &&
        listingId > 0 &&
        merchantId != null &&
        merchantId > 0;

    if (title.trim().isEmpty && price <= 0) {
      return Scaffold(
        appBar: AppBar(title: Text('Listing')),
        body: Center(child: Text('Listing not available.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Listing')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_detailLoading) const LinearProgressIndicator(),
          if (_detailError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Load failed: $_detailError',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          SafeImage(
            url: img,
            height: 220,
            width: double.infinity,
            borderRadius: BorderRadius.circular(12),
          ),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('NGN $price',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (desc.isNotEmpty) Text(desc),
          if (isDemo) ...[
            const SizedBox(height: 8),
            const Text(
              'Demo listing label only. Purchase is allowed if backend rules pass.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
          const Divider(height: 28),
          const Text('Delivery details',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          TextField(
            controller: _pickupCtrl,
            decoration: const InputDecoration(
                labelText: 'Pickup', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dropoffCtrl,
            decoration: const InputDecoration(
                labelText: 'Dropoff', border: OutlineInputBorder()),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _deliveryFeeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Delivery fee (NGN)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          if (isOwnListing)
            const Text("You can't buy your own listing.",
                style: TextStyle(color: Colors.redAccent)),
          ElevatedButton(
            onPressed: _busy || !canBuy ? null : _buyNowAndRequestDelivery,
            child: Text(
              _busy
                  ? 'Processing...'
                  : (canBuy
                      ? 'Buy Now + Request Delivery'
                      : 'Not available yet'),
            ),
          ),
        ],
      ),
    );
  }
}
