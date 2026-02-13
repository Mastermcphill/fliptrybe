import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/app_tokens.dart';

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
        if (DateTime.now().second % 30 == 0) {
          _loadTicker();
        }
      });
    }
  }

  Future<void> _loadTicker() async {
    try {
      final res = await ApiClient.instance.getJson(ApiConfig.api('/public/sales_ticker?limit=8'));
      if (res is Map && res['items'] is List) {
        final list = (res['items'] as List)
            .map((e) => (e is Map ? (e['text'] ?? '') : '').toString())
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
      // Ticker is optional.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Alignment _heroAlignment(BoxConstraints c) {
    final r = c.maxHeight / (c.maxWidth == 0 ? 1 : c.maxWidth);
    if (r > 1.7) return const Alignment(0, -0.25);
    return Alignment.center;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final alignment = _heroAlignment(c);
            final isCompact = c.maxWidth < 360 || c.maxHeight < 700;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FTCard(
                    padding: const EdgeInsets.all(AppTokens.s12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppTokens.r16),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
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
                                        scheme.scrim.withValues(alpha: 0.18),
                                        scheme.scrim.withValues(alpha: 0.55),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_items.isNotEmpty)
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.all(AppTokens.s12),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppTokens.s12,
                                          vertical: AppTokens.s8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: scheme.surface.withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(AppTokens.r12),
                                          border: Border.all(color: scheme.outlineVariant),
                                        ),
                                        child: AnimatedSwitcher(
                                          duration: AppTokens.d200,
                                          child: Text(
                                            _items[_idx],
                                            key: ValueKey(_items[_idx]),
                                            maxLines: isCompact ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w800,
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
                        const SizedBox(height: AppTokens.s16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s12,
                            vertical: AppTokens.s8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            'FlipTrybe',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppTokens.s12),
                        Text(
                          'Declutter Marketplace +\nShortlet Stays.',
                          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(height: AppTokens.s8),
                        Text(
                          'Browse immediately, then sign in only when you are ready to transact.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.s16),
                  FTSectionContainer(
                    title: 'Start Browsing',
                    subtitle: 'Guest mode is enabled for marketplace and shortlets.',
                    child: Column(
                      children: [
                        if (widget.onBrowseMarketplace != null)
                          FTPrimaryButton(
                            onPressed: widget.onBrowseMarketplace,
                            icon: Icons.storefront_outlined,
                            label: 'Browse Marketplace',
                          ),
                        if (widget.onBrowseMarketplace != null && widget.onBrowseShortlets != null)
                          const SizedBox(height: AppTokens.s8),
                        if (widget.onBrowseShortlets != null)
                          FTSecondaryButton(
                            onPressed: widget.onBrowseShortlets,
                            icon: Icons.home_work_outlined,
                            label: 'Browse Shortlets',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.s12),
                  FTPrimaryButton(
                    onPressed: widget.onLogin,
                    label: 'Login',
                  ),
                  const SizedBox(height: AppTokens.s8),
                  FTButton(
                    onPressed: widget.onSignup,
                    variant: FTButtonVariant.ghost,
                    expand: true,
                    label: 'Sign up (Choose role)',
                  ),
                  const SizedBox(height: AppTokens.s12),
                  Text(
                    'Guest browsing is open. Login is required for buy, checkout, sell, and booking actions.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
