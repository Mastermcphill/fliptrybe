import 'package:flutter/material.dart';

import '../../ui/components/ft_components.dart';
import '../../ui/theme/ft_tokens.dart';
import '../safe_image.dart';

class ListingCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final bool compact;

  const ListingCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.isFavorite,
    required this.onToggleFavorite,
    this.compact = false,
  });

  String _price(dynamic value) {
    final p = value is num
        ? value.toDouble()
        : double.tryParse(value.toString()) ?? 0;
    return '₦${p.toStringAsFixed(0)}';
  }

  String _timeAgo(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = (item['title'] ?? 'Untitled listing').toString();
    final location = [
      (item['city'] ?? '').toString(),
      (item['state'] ?? '').toString(),
    ].where((v) => v.trim().isNotEmpty).join(', ');
    final condition = (item['condition'] ?? '').toString();
    final created = (item['created_at'] ?? '').toString();
    final image = (item['image_path'] ?? item['image'] ?? '').toString();
    final boosted = item['is_boosted'] == true;
    final deliveryEnabled = item['delivery_enabled'] == true ||
        item['delivery_enabled']?.toString().toLowerCase() == 'true';
    final inspectionEnabled = item['inspection_enabled'] == true ||
        item['inspection_enabled']?.toString().toLowerCase() == 'true';

    return InkWell(
      borderRadius: BorderRadius.circular(FTTokens.radiusMd),
      onTap: onTap,
      child: FTCard(
        padding: const EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                AspectRatio(
                  aspectRatio: compact ? 1.35 : 1.2,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(FTTokens.radiusMd),
                    ),
                    child: image.trim().isEmpty
                        ? Container(
                            color: const Color(0xFFE2E8F0),
                            child: const Center(
                              child: Icon(Icons.image_outlined,
                                  size: 34, color: Color(0xFF94A3B8)),
                            ),
                          )
                        : SafeImage(
                            url: image,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(FTTokens.radiusMd),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onToggleFavorite,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.redAccent : Colors.black87,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
                if (boosted)
                  const Positioned(
                    left: 8,
                    top: 8,
                    child: FTPill(
                      text: 'Sponsored',
                      bgColor: Color(0xFF083344),
                      textColor: Colors.white,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _price(item['price']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      color: FTTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: FTTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (condition.trim().isNotEmpty)
                        FTPill(text: condition, bgColor: const Color(0xFFF1F5F9)),
                      if (deliveryEnabled)
                        const FTPill(
                          text: 'Delivery',
                          bgColor: Color(0xFFE0F2FE),
                        ),
                      if (inspectionEnabled)
                        const FTPill(
                          text: 'Inspection',
                          bgColor: Color(0xFFFFF7ED),
                        ),
                    ],
                  ),
                  if (location.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: FTTokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(created),
                    style: const TextStyle(
                      color: FTTokens.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
