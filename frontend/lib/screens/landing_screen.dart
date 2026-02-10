import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';

class LandingScreen extends StatefulWidget {
  final VoidCallback onLogin;
  final VoidCallback onSignup;

  const LandingScreen({
    super.key,
    required this.onLogin,
    required this.onSignup,
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

  BoxFit _heroFit(BoxConstraints c) {
    final r = c.maxHeight / (c.maxWidth == 0 ? 1 : c.maxWidth);
    // Use fitWidth on tall screens to avoid aggressive cropping.
    if (r > 1.7) return BoxFit.fitWidth;
    return BoxFit.cover;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final alignment = _heroAlignment(c);
          final fit = _heroFit(c);
          final isCompact = c.maxWidth < 360;
          final headlineSize = isCompact ? 30.0 : 36.0;
          final bodySize = isCompact ? 14.0 : 15.0;
          final ctaHeight = isCompact ? 48.0 : 52.0;
          final ctaRadius = isCompact ? 12.0 : 14.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              // Responsive hero crop for iOS/Android/Mac/Windows
              Image.asset(
                'assets/images/landing_hero.jpg',
                fit: fit,
                alignment: alignment,
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.black.withOpacity(0.78),
                    ],
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Floating live confirmation board
                      if (_items.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: Text(
                              _items[_idx],
                              key: ValueKey(_items[_idx]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withOpacity(0.18)),
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
                      const SizedBox(height: 16),
                      Text(
                        "Trade with trust.\nMove with confidence.",
                        style: TextStyle(
                          fontSize: headlineSize,
                          height: 1.05,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Listings, inspections, and delivery that keep your money safe.\nBuilt for real-world hustle, without the chaos.",
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.45,
                          color: Colors.white.withOpacity(0.92),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
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
                            side: BorderSide(color: Colors.white.withOpacity(0.75)),
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
                        "Merchants can sell globally, while we handle inspection + delivery in Nigeria.",
                        style: TextStyle(color: Colors.white.withOpacity(0.85), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
