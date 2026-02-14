import 'package:flutter/material.dart';

class SafeImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SafeImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  bool _isValidHttpImage(String? u) {
    if (u == null) return false;
    final s = u.trim();
    if (s.isEmpty) return false;

    final lower = s.toLowerCase();

    // Only allow http/https network images
    if (!(lower.startsWith('http://') || lower.startsWith('https://')))
      return false;

    // Block svg (Image.network won’t render it properly)
    if (lower.endsWith('.svg')) return false;

    // Block data URIs to avoid huge memory spikes
    if (lower.startsWith('data:')) return false;

    // If URL likely returns HTML (common error pages)
    if (lower.contains('.html') || lower.contains('text/html')) return false;

    return true;
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.apartment, color: Colors.grey.shade600),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = url?.trim();

    final Widget child = _isValidHttpImage(u)
        ? Image.network(
            u!,
            width: width,
            height: height,
            fit: fit,

            // Huge performance win on emulator: decode to roughly widget size
            cacheWidth: width != null ? (width!.clamp(1, 2000)).toInt() : null,

            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stack) => _placeholder(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: width,
                height: height,
                color: Colors.grey.shade200,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            },
          )
        : _placeholder();

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
