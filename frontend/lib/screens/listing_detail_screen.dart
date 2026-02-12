import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/listing_service.dart';
import '../services/marketplace_prefs_service.dart';
import '../services/merchant_service.dart';
import '../services/order_service.dart';
import '../utils/formatters.dart';
import '../ui/components/ft_components.dart';
import '../widgets/email_verification_dialog.dart';
import '../widgets/listing/listing_card.dart';
import '../widgets/safe_image.dart';
import 'order_detail_screen.dart';
import 'support_chat_screen.dart';

class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({super.key, required this.listing});

  final Map<String, dynamic> listing;

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  final _listings = ListingService();
  final _orders = OrderService();
  final _auth = AuthService();
  final _merchantSvc = MerchantService();
  final _prefs = MarketplacePrefsService();

  final _pickupCtrl = TextEditingController(text: 'Ikeja, Lagos');
  final _dropoffCtrl = TextEditingController(text: 'Lekki, Lagos');
  final _deliveryFeeCtrl = TextEditingController(text: '1500');
  final _pageCtrl = PageController();

  bool _busy = false;
  bool _loading = false;
  bool _loadingSimilar = false;
  bool _followBusy = false;
  bool _following = false;
  Set<int> _favoriteIds = <int>{};
  int _imageIndex = 0;
  int _followersCount = 0;
  int? _viewerId;
  Map<String, dynamic> _detail = const {};
  List<String> _images = const [];
  List<Map<String, dynamic>> _similar = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _detail = Map<String, dynamic>.from(widget.listing);
    _images = _extractImages(_detail);
    _loadDetail();
    _loadViewer();
    _loadSimilar();
    _loadFollowState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _dropoffCtrl.dispose();
    _deliveryFeeCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final id = _asInt(widget.listing['id']);
    if (id == null || id <= 0) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _listings.getListing(id);
      if (data.isNotEmpty && mounted) {
        setState(() {
          _detail = data;
          _images = _extractImages(data);
        });
        _loadFollowState();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadViewer() async {
    final profile = await _auth.me();
    if (!mounted) return;
    setState(() => _viewerId = _asInt(profile?['id']));
    _loadFollowState();
  }

  int _merchantId() {
    return _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']) ??
        0;
  }

  Future<void> _loadFollowState() async {
    final merchantId = _merchantId();
    if (merchantId <= 0) return;
    try {
      final values = await Future.wait([
        _merchantSvc.followStatus(merchantId),
        _merchantSvc.followersCount(merchantId),
      ]);
      if (!mounted) return;
      setState(() {
        _following = values[0]['following'] == true;
        _followersCount =
            int.tryParse((values[1]['followers'] ?? 0).toString()) ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    final merchantId = _merchantId();
    if (_followBusy || merchantId <= 0) return;
    if (_viewerId != null && merchantId == _viewerId) {
      _toast('You cannot follow your own merchant profile.');
      return;
    }
    setState(() => _followBusy = true);
    try {
      final response = _following
          ? await _merchantSvc.unfollowMerchant(merchantId)
          : await _merchantSvc.followMerchant(merchantId);
      if (response['ok'] != true && mounted) {
        _toast((response['message'] ?? 'Unable to update follow state')
            .toString());
      }
      await _loadFollowState();
    } catch (e) {
      if (mounted) _toast('Unable to update follow state: $e');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _loadSimilar() async {
    setState(() => _loadingSimilar = true);
    try {
      final all = await _listings.listListings();
      if (!mounted) return;
      final selfId = _asInt(widget.listing['id']) ?? 0;
      final category = (_detail['category'] ?? '').toString().toLowerCase();
      final state = (_detail['state'] ?? '').toString().toLowerCase();
      final rows = all
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .where((row) => (_asInt(row['id']) ?? 0) != selfId)
          .toList();
      rows.sort((a, b) {
        int score(Map<String, dynamic> row) {
          int s = 0;
          if ((row['category'] ?? '').toString().toLowerCase() == category)
            s += 2;
          if ((row['state'] ?? '').toString().toLowerCase() == state) s += 1;
          return s;
        }

        return score(b).compareTo(score(a));
      });
      setState(() {
        _similar = rows.take(8).toList();
        _loadingSimilar = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSimilar = false);
    }
  }

  Future<void> _loadFavorites() async {
    final values = await _prefs.loadFavorites();
    if (!mounted) return;
    setState(() => _favoriteIds = values);
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = _asInt(item['id']);
    if (id == null || id <= 0) return;
    final next = <int>{..._favoriteIds};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favoriteIds = next);
    await _prefs.saveFavorites(next);
  }

  List<String> _extractImages(Map<String, dynamic> data) {
    final images = <String>[];
    final primary =
        (data['image_path'] ?? data['image'] ?? '').toString().trim();
    if (primary.isNotEmpty) images.add(primary);
    final raw = data['images'];
    if (raw is List) {
      for (final item in raw) {
        final v = item?.toString().trim() ?? '';
        if (v.isNotEmpty && !images.contains(v)) images.add(v);
      }
    }
    return images;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  String _money(dynamic value) => formatNaira(_asDouble(value));

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buyNowAndRequestDelivery() async {
    final merchantId = _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']);
    if (_viewerId != null && merchantId != null && merchantId == _viewerId) {
      _toast("You can't place an order on your own listing.");
      return;
    }

    final listingId = _asInt(_detail['id']);
    if (listingId == null ||
        listingId <= 0 ||
        merchantId == null ||
        merchantId <= 0) {
      _toast('Listing not available for checkout.');
      return;
    }

    setState(() => _busy = true);
    try {
      final amount = _asDouble(_detail['price']);
      final deliveryFee = _asDouble(_deliveryFeeCtrl.text.trim());

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
            (result['message'] ?? result['error'] ?? 'Order failed').toString();
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
          : Map<String, dynamic>.from(result);
      final orderId = _asInt(orderRaw['id']);
      if (orderId == null || !mounted) return;

      _toast('Order created successfully.');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
      );
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF334155)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_detail['title'] ?? 'Listing').toString();
    final description = (_detail['description'] ?? '').toString();
    final condition = (_detail['condition'] ?? 'Used').toString();
    final location = [
      (_detail['city'] ?? '').toString(),
      (_detail['state'] ?? '').toString(),
    ].where((v) => v.trim().isNotEmpty).join(', ');
    final posted = formatRelativeTime(_detail['created_at']);
    final merchantName =
        (_detail['merchant_name'] ?? _detail['shop_name'] ?? 'Merchant')
            .toString();
    final merchantId = _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']);
    final isOwnListing =
        _viewerId != null && merchantId != null && merchantId == _viewerId;

    return FTScaffold(
      title: 'Listing Details',
      actions: [
        IconButton(
          onPressed: _loading ? null : _loadDetail,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (_error != null) ...[
            FTErrorState(
                message: 'Detail refresh failed: $_error',
                onRetry: _loadDetail),
            const SizedBox(height: 8),
          ],
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _images.isEmpty
                  ? Container(
                      color: const Color(0xFFE2E8F0),
                      child: const Center(
                          child: Icon(Icons.image_outlined, size: 34)),
                    )
                  : PageView.builder(
                      controller: _pageCtrl,
                      itemCount: _images.length,
                      onPageChanged: (index) =>
                          setState(() => _imageIndex = index),
                      itemBuilder: (_, index) {
                        return SafeImage(
                          url: _images[index],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          borderRadius: BorderRadius.circular(14),
                        );
                      },
                    ),
            ),
          ),
          if (_images.length > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_images.length, (index) {
                final active = index == _imageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: active ? 20 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF0E7490)
                        : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _money(_detail['price']),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaChip(Icons.location_on_outlined,
                  location.trim().isEmpty ? 'Location not set' : location),
              _metaChip(Icons.sell_outlined, condition),
              _metaChip(Icons.schedule_outlined, posted),
            ],
          ),
          const SizedBox(height: 14),
          FTSectionContainer(
            title: 'Seller',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE2E8F0),
                child: Text(
                  merchantName.isEmpty ? 'M' : merchantName[0].toUpperCase(),
                ),
              ),
              title: Text(merchantName),
              subtitle: Text(
                'Seller #${merchantId?.toString() ?? '-'} • Rating 4.8 • $_followersCount followers',
              ),
              trailing: OutlinedButton(
                onPressed: _followBusy ? null : _toggleFollow,
                child: Text(_following ? 'Following' : 'Follow'),
              ),
            ),
          ),
          const SizedBox(height: 10),
          FTSectionContainer(
            title: 'About this listing',
            child: Text(
              description.trim().isEmpty
                  ? 'No description provided by merchant.'
                  : description,
            ),
          ),
          const SizedBox(height: 10),
          FTSectionContainer(
            title: 'Delivery and inspection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _pickupCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Pickup',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dropoffCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Dropoff',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _deliveryFeeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Delivery fee (₦)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (isOwnListing) ...[
                  const SizedBox(height: 10),
                  const Text(
                    "You can't purchase your own listing.",
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Similar items',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (_loadingSimilar) const Text('Loading...')
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingSimilar)
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, __) => const SizedBox(
                  width: 205,
                  child: FTListCardSkeleton(),
                ),
              ),
            )
          else if (_similar.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('No similar items available right now.'),
              ),
            )
          else
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _similar.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  final item = _similar[index];
                  return SizedBox(
                    width: 205,
                    child: ListingCard(
                      item: item,
                      isFavorite:
                          _favoriteIds.contains(_asInt(item['id']) ?? -1),
                      onToggleFavorite: () => _toggleFavorite(item),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ListingDetailScreen(listing: item),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SupportChatScreen()),
                  ),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Chat Admin'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _busy || isOwnListing ? null : _buyNowAndRequestDelivery,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(_busy ? 'Processing...' : 'Buy Now'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
