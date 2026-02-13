import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

class LandingScreen extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignup;
  final VoidCallback? onBrowseMarketplace;
  final VoidCallback? onBrowseShortlets;
  final bool enableTicker;

  const LandingScreen({
    super.key,
    required this.onLogin,
    required this.onSignup,
    this.onBrowseMarketplace,
    this.onBrowseShortlets,
    this.enableTicker = true,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  Timer? _timer;
  List<String> _items = const [];
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    if (widget.enableTicker) {
      _loadTicker();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (_items.isNotEmpty) {
          setState(() => _idx = (_idx + 1) % _items.length);
        }
        // refresh occasionally
        if (DateTime.now().second % 30 == 0) {
          _loadTicker();
        }
      });
    }
  }

  Future<void> _loadTicker() async {
    try {
      final res = await ApiClient.instance.getJson(ApiConfig.api("/public/sales_ticker?limit=8"));
      if (res is Map && res["items"] is List) {
        final list = (res["items"] as List)
            .map((e) => (e is Map ? (e["text"] ?? "") : "").toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (!mounted) return;
        if (list.isNotEmpty) {
          setState(() {
            _items = list;
            _idx = 0;
          });
        }
      }
    } catch (_) {
      // Silent: ticker is a nice-to-have on slow networks.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Alignment _heroAlignment(BoxConstraints c) {
    final r = c.maxHeight / (c.maxWidth == 0 ? 1 : c.maxWidth);
    // Taller screens (iOS/Android portrait) often need a slight upward crop.
    if (r > 1.7) return const Alignment(0, -0.25);
    return Alignment.center;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final alignment = _heroAlignment(c);
            final isCompact = c.maxWidth < 360 || c.maxHeight < 700;
            final headlineSize = isCompact ? 28.0 : 36.0;
            final bodySize = isCompact ? 13.0 : 15.0;
            final ctaHeight = isCompact ? 46.0 : 52.0;
            final ctaRadius = isCompact ? 12.0 : 14.0;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 30),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                'assets/images/landing_hero.jpg',
                                fit: BoxFit.cover,
                                alignment: alignment,
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.35),
                                      Colors.black.withValues(alpha: 0.65),
                                    ],
                                  ),
                                ),
                              ),
                              if (_items.isNotEmpty)
                                Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 400),
                                        child: Text(
                                          _items[_idx],
                                          key: ValueKey(_items[_idx]),
                                          maxLines: isCompact ? 1 : 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                        ),
                        child: const Text(
                          "FlipTrybe",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Declutter Marketplace +\nShortlet Stays.",
                        style: TextStyle(
                          fontSize: headlineSize,
                          height: 1.05,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "FlipTrybe combines Declutter Marketplace and Shortlet Stays. Browse immediately, then sign in only when you are ready to transact.",
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (widget.onBrowseMarketplace != null ||
                          widget.onBrowseShortlets != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16)),
                          ),
                          child: Column(
                            children: [
                              if (widget.onBrowseMarketplace != null)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: widget.onBrowseMarketplace,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0EA5E9),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(ctaRadius),
                                      ),
                                    ),
                                    icon: const Icon(Icons.storefront_outlined),
                                    label: const Text('Browse Marketplace'),
                                  ),
                                ),
                              if (widget.onBrowseMarketplace != null &&
                                  widget.onBrowseShortlets != null)
                                const SizedBox(height: 8),
                              if (widget.onBrowseShortlets != null)
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: widget.onBrowseShortlets,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF22C55E),
                                      foregroundColor: const Color(0xFF052E16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(ctaRadius),
                                      ),
                                    ),
                                    icon: const Icon(Icons.home_work_outlined),
                                    label: const Text('Browse Shortlets'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      if (widget.onBrowseMarketplace != null ||
                          widget.onBrowseShortlets != null)
                        const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: ctaHeight,
                        child: ElevatedButton(
                          onPressed: widget.onLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(ctaRadius),
                            ),
                          ),
                          child: const Text(
                            "Login",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: ctaHeight,
                        child: OutlinedButton(
                          onPressed: widget.onSignup,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(ctaRadius),
                            ),
                          ),
                          child: const Text(
                            "Sign up (Choose role)",
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Guest browsing is open. Login is required for buy, checkout, sell, and booking actions.",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
