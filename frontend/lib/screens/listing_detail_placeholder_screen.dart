import 'package:flutter/material.dart';

import '../services/listing_service.dart';
import '../services/shortlet_service.dart';
import '../widgets/safe_image.dart';

class ListingDetailPlaceholderScreen extends StatefulWidget {
  final int? id;
  final String? title;
  final dynamic price;
  final String? imageUrl;
  final String? location;
  final String? category;

  const ListingDetailPlaceholderScreen({
    super.key,
    this.id,
    this.title,
    this.price,
    this.imageUrl,
    this.location,
    this.category,
  });

  @override
  State<ListingDetailPlaceholderScreen> createState() =>
      _ListingDetailPlaceholderScreenState();
}

class _ListingDetailPlaceholderScreenState
    extends State<ListingDetailPlaceholderScreen> {
  final _listingSvc = ListingService();
  final _shortletSvc = ShortletService();

  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _detail;

  String _formatPrice(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString();
    return s.isEmpty ? '' : '₦$s';
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  String _asString(dynamic v) {
    return (v ?? '').toString();
  }

  @override
  void initState() {
    super.initState();
    _detail = {
      'id': widget.id,
      'title': widget.title,
      'price': widget.price,
      'image': widget.imageUrl,
      'location': widget.location,
      'category': widget.category,
    };
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final id = widget.id;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final isShortlet =
          (widget.category ?? '').toLowerCase().contains('shortlet');
      final data = isShortlet
          ? await _shortletSvc.getShortlet(id)
          : await _listingSvc.getListing(id);
      if (data.isNotEmpty) {
        setState(() {
          _detail = data;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _detail ?? {};
    final displayTitle = (_asString(m['title']).trim().isEmpty)
        ? 'Listing Details'
        : _asString(m['title']).trim();
    final priceText = _formatPrice(m['price'] ?? m['nightly_price']);
    final locationText = _asString(m['location']).trim().isNotEmpty
        ? _asString(m['location']).trim()
        : [m['locality'], m['city'], m['state']]
            .map(_asString)
            .where((x) => x.trim().isNotEmpty)
            .join(', ');
    final categoryText = _asString(m['category']).trim();
    final image = _asString(m['image']);
    final imagePath = _asString(m['image_path']);
    final imageUrl = image.isNotEmpty ? image : imagePath;
    final hasImage = imageUrl.trim().isNotEmpty;
    final desc = _asString(m['description']).trim();
    final seller = _asString(m['seller_name']).trim().isNotEmpty
        ? _asString(m['seller_name']).trim()
        : _asString(m['owner_name']).trim().isNotEmpty
            ? _asString(m['owner_name']).trim()
            : _asString(m['merchant_name']).trim();
    final id = _asInt(m['id'] ?? widget.id);

    return Scaffold(
      appBar: AppBar(title: Text(displayTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Load failed: $_error',
                  style: const TextStyle(color: Colors.redAccent)),
            ),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SafeImage(
                      url: imageUrl,
                      height: 200,
                      width: double.infinity,
                    ),
                  )
                : const Center(
                    child: Icon(Icons.image_outlined,
                        size: 48, color: Color(0xFF94A3B8)),
                  ),
          ),
          const SizedBox(height: 16),
          if (priceText.isNotEmpty)
            Text(
              priceText,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          if (priceText.isNotEmpty) const SizedBox(height: 8),
          if (locationText.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 18, color: Color(0xFF475569)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locationText,
                    style: const TextStyle(color: Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          if (categoryText.isNotEmpty) const SizedBox(height: 6),
          if (categoryText.isNotEmpty)
            Text(
              categoryText,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          if (seller.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Seller: $seller',
                style: const TextStyle(color: Color(0xFF475569))),
          ],
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(desc),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              id == null
                  ? 'More details coming soon.'
                  : 'Full details coming soon.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
