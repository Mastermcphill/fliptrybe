import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/analytics_hooks.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/listing_service.dart';
import '../services/marketplace_catalog_service.dart';
import '../services/marketplace_prefs_service.dart';
import '../services/merchant_service.dart';
import '../services/order_service.dart';
import '../services/payment_service.dart';
import '../services/auth_gate_service.dart';
import '../utils/formatters.dart';
import '../ui/components/ft_components.dart';
import '../widgets/phone_verification_dialog.dart';
import '../widgets/listing/listing_card.dart';
import '../widgets/safe_image.dart';
import 'cart_screen.dart';
import 'manual_payment_instructions_screen.dart';
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
  final _payments = PaymentService();
  final _auth = AuthService();
  final _merchantSvc = MerchantService();
  final _prefs = MarketplacePrefsService();
  final _catalog = MarketplaceCatalogService();
  final _cart = CartService();

  final _pickupCtrl = TextEditingController(text: 'Ikeja, Lagos');
  final _dropoffCtrl = TextEditingController(text: 'Lekki, Lagos');
  final _deliveryFeeCtrl = TextEditingController(text: '1500');
  final _pageCtrl = PageController();

  bool _busy = false;
  bool _loading = false;
  bool _loadingSimilar = false;
  bool _followBusy = false;
  bool _following = false;
  bool _viewSent = false;
  Set<int> _favoriteIds = <int>{};
  int _imageIndex = 0;
  int _followersCount = 0;
  int? _viewerId;
  Map<String, dynamic> _detail = const {};
  Map<String, dynamic> _merchantCard = const {};
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
    _loadMerchantCard();
    _loadFavorites();
    _recordViewOnce();
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
        final payload = data['listing'] is Map
            ? Map<String, dynamic>.from(data['listing'] as Map)
            : data;
        setState(() {
          _detail = payload;
          _images = _extractImages(payload);
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

  Future<void> _loadMerchantCard() async {
    final merchantId = _merchantId();
    if (merchantId <= 0) return;
    try {
      final payload = await _merchantSvc.publicMerchantCard(merchantId);
      if (!mounted) return;
      if (payload['ok'] == true && payload['merchant'] is Map) {
        setState(() {
          _merchantCard = Map<String, dynamic>.from(payload['merchant'] as Map);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFollowAuthorized() async {
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

  Future<void> _toggleFollow() async {
    await requireAuthForAction(
      context,
      action: 'follow merchants',
      onAuthorized: _toggleFollowAuthorized,
    );
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
          if ((row['category'] ?? '').toString().toLowerCase() == category) {
            s += 2;
          }
          if ((row['state'] ?? '').toString().toLowerCase() == state) {
            s += 1;
          }
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

  Future<void> _toggleFavoriteAuthorized(Map<String, dynamic> item) async {
    final id = _asInt(item['id']);
    if (id == null || id <= 0) return;
    final next = <int>{..._favoriteIds};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favoriteIds = next);
    final remote = await _catalog.favoriteListing(
      listingId: id,
      favorite: next.contains(id),
    );
    if (remote['ok'] == true && mounted) {
      setState(() {
        _detail['favorites_count'] = int.tryParse(
                '${remote['favorites_count'] ?? _detail['favorites_count'] ?? 0}') ??
            0;
      });
    }
    await _prefs.saveFavorites(next);
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    await requireAuthForAction(
      context,
      action: 'save listings to your watchlist',
      onAuthorized: () => _toggleFavoriteAuthorized(item),
    );
  }

  Future<void> _recordViewOnce() async {
    if (_viewSent) return;
    final listingId = _asInt(_detail['id']);
    if (listingId == null || listingId <= 0) return;
    _viewSent = true;
    final payload = await _catalog.recordListingView(
      listingId,
      sessionKey: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    if (payload['ok'] == true) {
      await AnalyticsHooks.instance.listingView(listingId: listingId);
      setState(() {
        _detail['views_count'] = int.tryParse(
                '${payload['views_count'] ?? _detail['views_count'] ?? 0}') ??
            0;
        _detail['heat_level'] =
            (payload['heat_level'] ?? _detail['heat_level'] ?? '').toString();
      });
    }
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

  bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    final text = v.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  String _yesNo(dynamic v) {
    final parsed = _asBool(v);
    if (parsed == null) return '';
    return parsed ? 'Yes' : 'No';
  }

  String _maskVin(String value) {
    final vin = value.trim();
    if (vin.length <= 4) return vin;
    final tail = vin.substring(vin.length - 4);
    return '*************$tail';
  }

  String _money(dynamic value) => formatNaira(_asDouble(value));

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addToCartAuthorized() async {
    final listingId = _asInt(_detail['id']);
    if (listingId == null || listingId <= 0) {
      _toast('Listing is unavailable for cart.');
      return;
    }
    final res = await _cart.addItem(listingId: listingId, quantity: 1);
    if (res['ok'] == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Added to cart.'),
          action: SnackBarAction(
            label: 'Open cart',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
            },
          ),
        ),
      );
      return;
    }
    _toast((res['message'] ?? 'Unable to add item to cart').toString());
  }

  Future<void> _addToCart() async {
    await requireAuthForAction(
      context,
      action: 'add items to cart',
      onAuthorized: _addToCartAuthorized,
    );
  }

  Future<void> _buyNowAndRequestDeliveryAuthorized() async {
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
        paymentReference: '',
      );

      if (result['ok'] != true) {
        final msg =
            (result['message'] ?? result['error'] ?? 'Order failed').toString();
        if (ApiService.isPhoneNotVerified(result) ||
            ApiService.isPhoneNotVerified(msg)) {
          if (!mounted) return;
          await showPhoneVerificationRequiredDialog(
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
      await AnalyticsHooks.instance.orderCreated(orderId: orderId);
      final orderTotal = _asDouble(orderRaw['total_price']) > 0
          ? _asDouble(orderRaw['total_price'])
          : amount + deliveryFee;

      final paymentInit = await _payments.initialize(
        amount: orderTotal,
        purpose: 'order',
        orderId: orderId,
      );
      if (!mounted) return;
      if (paymentInit['ok'] != true) {
        await AnalyticsHooks.instance.paymentFail(
          channel: 'order_checkout',
          reason:
              (paymentInit['error'] ?? paymentInit['message'] ?? '').toString(),
        );
        final initMsg = (paymentInit['message'] ??
                paymentInit['error'] ??
                'Payment initialization failed')
            .toString();
        _toast(initMsg);
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderId)),
        );
        return;
      }

      final initMode = (paymentInit['mode'] ?? '').toString().toLowerCase();
      await AnalyticsHooks.instance.paymentSuccess(
        channel: initMode.isEmpty ? 'wallet' : initMode,
        reference: (paymentInit['reference'] ?? '').toString(),
      );

      _toast('Order created successfully.');
      if (initMode == 'manual_company_account') {
        final instructions = paymentInit['manual_instructions'] is Map
            ? Map<String, dynamic>.from(
                paymentInit['manual_instructions'] as Map)
            : <String, dynamic>{};
        final paymentIntentRaw = paymentInit['payment_intent_id'];
        final paymentIntentId = paymentIntentRaw is int
            ? paymentIntentRaw
            : int.tryParse((paymentIntentRaw ?? '').toString());
        final reference = (paymentInit['reference'] ?? '').toString();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManualPaymentInstructionsScreen(
              orderId: orderId,
              amount: orderTotal,
              reference: reference,
              paymentIntentId: paymentIntentId,
              initialInstructions: instructions,
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => OrderDetailScreen(orderId: orderId)),
        );
      }
    } catch (e) {
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyNowAndRequestDelivery() async {
    await requireAuthForAction(
      context,
      action: 'buy this listing',
      onAuthorized: _buyNowAndRequestDeliveryAuthorized,
    );
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

  Widget _specTableCard({
    required String title,
    required List<MapEntry<String, String>> rows,
  }) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return FTSectionContainer(
      title: title,
      child: Column(
        children: rows.map((entry) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    entry.key,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.value,
                    softWrap: true,
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  List<MapEntry<String, String>> _vehicleSpecRows(Map<String, dynamic> detail) {
    final meta = detail['vehicle_metadata'] is Map
        ? Map<String, dynamic>.from(detail['vehicle_metadata'] as Map)
        : <String, dynamic>{};
    String read(String key, [String fallback = '']) {
      final direct = (detail[key] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;
      final nested = (meta[key] ?? fallback).toString().trim();
      return nested;
    }

    final rows = <MapEntry<String, String>>[
      MapEntry('Make', read('vehicle_make', read('make'))),
      MapEntry('Model', read('vehicle_model', read('model'))),
      MapEntry('Year', read('vehicle_year', read('year_of_manufacture'))),
      MapEntry('Mileage', read('mileage')),
      MapEntry('Transmission', read('transmission')),
      MapEntry('Fuel', read('fuel_type')),
      MapEntry('Drivetrain', read('drivetrain')),
      MapEntry('Engine', read('engine_size')),
      MapEntry('Cylinders', read('number_of_cylinders')),
      MapEntry('Color', read('color')),
      MapEntry('Interior', read('interior_color')),
      MapEntry('Condition', read('condition')),
      MapEntry('Registered', _yesNo(meta['registered_car'])),
      MapEntry(
          'VIN',
          read('vin').trim().isEmpty
              ? ''
              : _maskVin(read('vin'))),
    ];
    return rows
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
  }

  Widget _solarBundleSummaryCard(Map<String, dynamic> detail) {
    final category = (detail['category'] ?? '').toString().toLowerCase();
    final meta = detail['energy_metadata'] is Map
        ? Map<String, dynamic>.from(detail['energy_metadata'] as Map)
        : <String, dynamic>{};
    if (!category.contains('solar bundle')) {
      return const SizedBox.shrink();
    }
    String read(String key, [String fallback = '']) =>
        (meta[key] ?? detail[key] ?? fallback).toString().trim();

    final accessoryText = read('included_accessories');
    return FTSectionContainer(
      title: 'Solar Bundle Summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaChip(Icons.electrical_services_outlined,
                  read('inverter_brand_capacity', detail['inverter_capacity']?.toString() ?? 'N/A')),
              _metaChip(Icons.battery_charging_full_outlined,
                  '${read('battery_type')} ${read('battery_capacity_ah').isEmpty ? '' : '(${read('battery_capacity_ah')}Ah)'}'),
              _metaChip(Icons.solar_power_outlined,
                  '${read('solar_panel_wattage')}W x ${read('number_of_panels').isEmpty ? '-' : read('number_of_panels')}'),
              _metaChip(Icons.build_outlined,
                  'Install: ${_yesNo(meta['installation_included'])}'),
              _metaChip(Icons.verified_outlined,
                  read('warranty_length', 'Warranty not specified')),
            ],
          ),
          if (accessoryText.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Included components',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(accessoryText),
          ],
        ],
      ),
    );
  }

  List<MapEntry<String, String>> _realEstateSpecRows(Map<String, dynamic> detail) {
    final meta = detail['real_estate_metadata'] is Map
        ? Map<String, dynamic>.from(detail['real_estate_metadata'] as Map)
        : <String, dynamic>{};
    String read(String key, [String fallback = '']) {
      final direct = (detail[key] ?? '').toString().trim();
      if (direct.isNotEmpty) return direct;
      final nested = (meta[key] ?? fallback).toString().trim();
      return nested;
    }

    final rows = <MapEntry<String, String>>[
      MapEntry('Property Type', read('property_type')),
      MapEntry('Bedrooms', read('bedrooms')),
      MapEntry('Bathrooms', read('bathrooms')),
      MapEntry('Toilets', read('toilets')),
      MapEntry('Parking', read('parking_spaces')),
      MapEntry('Furnished', _yesNo(meta['furnished'] ?? detail['furnished'])),
      MapEntry('Serviced', _yesNo(meta['serviced'] ?? detail['serviced'])),
      MapEntry('Land Size', read('land_size')),
      MapEntry('Title Document', read('title_document_type')),
      MapEntry('Topography', read('topography')),
      MapEntry('Access Road', _yesNo(meta['access_road'])),
      MapEntry('Area', read('area', read('locality'))),
      MapEntry('City', read('city')),
      MapEntry('State', read('state')),
    ];
    return rows
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final title = (_detail['title'] ?? 'Listing').toString();
    final description = (_detail['description'] ?? '').toString();
    final listingType = (_detail['listing_type'] ?? '').toString().toLowerCase();
    final categoryText = (_detail['category'] ?? '').toString().toLowerCase();
    final condition = (_detail['condition'] ?? 'Used').toString();
    final location = [
      (_detail['city'] ?? '').toString(),
      (_detail['state'] ?? '').toString(),
    ].where((v) => v.trim().isNotEmpty).join(', ');
    final posted = formatRelativeTime(_detail['created_at']);
    final viewsCount = int.tryParse('${_detail['views_count'] ?? 0}') ?? 0;
    final favoritesCount =
        int.tryParse('${_detail['favorites_count'] ?? 0}') ?? 0;
    final heatLevel =
        (_detail['heat_level'] ?? '').toString().trim().toLowerCase();
    final heatText = heatLevel == 'hotter'
        ? 'Hotter'
        : heatLevel == 'hot'
            ? 'Hot'
            : '';
    final merchantName = (_merchantCard['name'] ??
            _detail['merchant_name'] ??
            _detail['shop_name'] ??
            'Merchant')
        .toString();
    final merchantPhoto = (_merchantCard['profile_image_url'] ??
            _detail['merchant_profile_image_url'] ??
            '')
        .toString()
        .trim();
    final followersCount = int.tryParse(
            '${_merchantCard['followers_count'] ?? _followersCount}') ??
        _followersCount;
    final merchantId = _asInt(_detail['user_id']) ??
        _asInt(_detail['merchant_id']) ??
        _asInt(_detail['owner_id']);
    final isOwnListing =
        _viewerId != null && merchantId != null && merchantId == _viewerId;
    final heroTag =
        'listing-image-${_detail['id'] ?? widget.listing['id'] ?? title}';
    final vehicleRows = _vehicleSpecRows(_detail);
    final realEstateRows = _realEstateSpecRows(_detail);
    final showVehicleSpecs = listingType == 'vehicle' || vehicleRows.isNotEmpty;
    final showRealEstateSpecs =
        listingType == 'real_estate' || categoryText.contains('house') || categoryText.contains('land');

    return FTScaffold(
      title: 'Listing Details',
      actions: [
        IconButton(
          onPressed: _loading ? null : _loadDetail,
          icon: const Icon(Icons.refresh),
        ),
      ],
      // ignore: sort_child_properties_last
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
            child: Hero(
              tag: heroTag,
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
              _metaChip(Icons.visibility_outlined, '$viewsCount views'),
              _metaChip(Icons.favorite_outline, '$favoritesCount watching'),
              if (heatText.isNotEmpty)
                _metaChip(Icons.local_fire_department_outlined, heatText),
            ],
          ),
          const SizedBox(height: 14),
          FTSectionContainer(
            title: 'Seller',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: merchantPhoto.isNotEmpty
                    ? NetworkImage(merchantPhoto)
                    : null,
                child: merchantPhoto.isNotEmpty
                    ? null
                    : Text(
                        merchantName.isEmpty
                            ? 'M'
                            : merchantName[0].toUpperCase(),
                      ),
              ),
              title: Text(merchantName),
              subtitle: Text(
                'Seller #${merchantId?.toString() ?? '-'} - Rating 4.8 - $followersCount followers',
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
          if (showVehicleSpecs) ...[
            const SizedBox(height: 10),
            _specTableCard(title: 'Vehicle Specifications', rows: vehicleRows),
          ],
          if (listingType == 'energy' || categoryText.contains('solar bundle')) ...[
            const SizedBox(height: 10),
            _solarBundleSummaryCard(_detail),
          ],
          if (showRealEstateSpecs) ...[
            const SizedBox(height: 10),
            _specTableCard(title: 'Property Specifications', rows: realEstateRows),
          ],
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
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final listingId = _asInt(_detail['id']) ?? 0;
                    final recipientId = _merchantId() > 0 ? _merchantId() : null;
                    if (listingId > 0) {
                      await AnalyticsHooks.instance
                          .listingContact(listingId: listingId);
                    }
                    if (!mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SupportChatScreen(
                          recipientUserId: recipientId,
                          listingId: listingId > 0 ? listingId : null,
                          title: recipientId != null
                              ? 'Enquire About Listing'
                              : 'Support',
                          initialHint: recipientId != null
                              ? 'Ask a question before payment'
                              : 'Message support',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Enquire'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || isOwnListing ? null : _addToCart,
                  icon: const Icon(Icons.add_shopping_cart_outlined),
                  label: const Text('Cart'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      _busy || isOwnListing ? null : _buyNowAndRequestDelivery,
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: Text(_busy ? '...' : 'Buy'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
