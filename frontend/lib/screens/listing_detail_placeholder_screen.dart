import 'package:flutter/material.dart';

class ListingDetailPlaceholderScreen extends StatelessWidget {
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

  String _formatPrice(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString();
    return s.isEmpty ? '' : '₦$s';
  }

  @override
  Widget build(BuildContext context) {
    final displayTitle = (title == null || title!.trim().isEmpty) ? 'Listing Details' : title!.trim();
    final priceText = _formatPrice(price);
    final locationText = location?.trim() ?? '';
    final categoryText = category?.trim() ?? '';
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(displayTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.image_not_supported_outlined, size: 48),
                      ),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.image_outlined, size: 48, color: Color(0xFF94A3B8)),
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
                const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF475569)),
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
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(
              id == null ? 'More details coming soon.' : 'Full details coming soon.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
