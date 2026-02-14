import 'package:flutter/material.dart';

import '../constants/ng_cities.dart';
import '../services/city_preference_service.dart';
import '../services/shortlet_service.dart';
import '../ui/components/ft_components.dart';
import '../ui/design/ft_tokens.dart';
import '../utils/auth_navigation.dart';
import '../utils/ft_routes.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';
import '../widgets/safe_image.dart';
import 'shortlet_detail_screen.dart';

class ShortletScreen extends StatefulWidget {
  const ShortletScreen({super.key});

  @override
  State<ShortletScreen> createState() => _ShortletScreenState();
}

class _ShortletScreenState extends State<ShortletScreen> {
  final _svc = ShortletService();
  final _cityPrefs = CityPreferenceService();
  final _searchCtrl = TextEditingController();

  String _selectedCity = defaultDiscoveryCity;
  String _selectedState = defaultDiscoveryState;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pref = await _cityPrefs.syncFromServer();
      final city = (pref['preferred_city'] ?? defaultDiscoveryCity).trim();
      final state = (pref['preferred_state'] ?? defaultDiscoveryState).trim();
      List<dynamic> raw = await _svc.recommendedShortlets(
        city: city,
        state: state,
        limit: 80,
      );
      if (raw.isEmpty) {
        raw = await _svc.listShortlets(state: state, city: city);
      }
      if (!mounted) return;
      setState(() {
        _selectedCity = city.isEmpty ? defaultDiscoveryCity : city;
        _selectedState = state.isEmpty ? defaultDiscoveryState : state;
        _all = raw
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (UIFeedback.shouldForceLogoutOn401(e)) {
        if (mounted) {
          UIFeedback.showErrorSnack(
              context, 'Session expired, please sign in again.');
        }
        await logoutToLanding(context);
        return;
      }
      final errorMessage = UIFeedback.mapDioErrorToMessage(e);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = errorMessage;
      });
      UIFeedback.showErrorSnack(context, errorMessage);
    }
  }

  Future<void> _pickCity() async {
    final scheme = Theme.of(context).colorScheme;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FTDesignTokens.radiusLg),
        ),
      ),
      builder: (ctx) {
        final ctrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModal) {
            final q = ctrl.text.trim().toLowerCase();
            final cities = nigeriaTieredCities
                .where((city) => q.isEmpty || city.toLowerCase().contains(q))
                .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: FTDesignTokens.md,
                  right: FTDesignTokens.md,
                  top: FTDesignTokens.sm,
                  bottom: MediaQuery.of(context).viewInsets.bottom +
                      FTDesignTokens.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Choose city'),
                      subtitle: Text(
                        'Shortlet recommendations prioritize your city first',
                      ),
                    ),
                    FTInput(
                      controller: ctrl,
                      onChanged: (_) => setModal(() {}),
                      hint: 'Search city',
                      prefixIcon: Icons.search,
                    ),
                    const SizedBox(height: FTDesignTokens.sm),
                    SizedBox(
                      height: 340,
                      child: ListView.builder(
                        itemCount: cities.length,
                        itemBuilder: (_, index) {
                          final city = cities[index];
                          return ListTile(
                            title: Text(city),
                            trailing: city == _selectedCity
                                ? Icon(
                                    Icons.check_circle,
                                    color: scheme.primary,
                                  )
                                : null,
                            onTap: () => Navigator.of(ctx).pop(city),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || selected.trim().isEmpty) return;
    await _cityPrefs.saveAndSync(
      preferredCity: selected.trim(),
      preferredState: _selectedState,
    );
    if (!mounted) return;
    await _load();
  }

  List<Map<String, dynamic>> _filtered() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((row) {
      final title = (row['title'] ?? '').toString().toLowerCase();
      final city = (row['city'] ?? '').toString().toLowerCase();
      final state = (row['state'] ?? '').toString().toLowerCase();
      return title.contains(q) || city.contains(q) || state.contains(q);
    }).toList(growable: false);
  }

  String _location(Map<String, dynamic> row) {
    final city = (row['city'] ?? '').toString().trim();
    final state = (row['state'] ?? '').toString().trim();
    if (city.isEmpty && state.isEmpty) return 'Location not set';
    if (city.isEmpty) return state;
    if (state.isEmpty) return city;
    return '$city, $state';
  }

  void _clearFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    _searchCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = _filtered();
    return FTScaffold(
      title: 'Haven Shortlets',
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _loading
          ? const _ShortletSkeleton()
          : _error != null
              ? FTErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    cacheExtent: 640,
                    padding: const EdgeInsets.fromLTRB(
                      FTDesignTokens.md,
                      FTDesignTokens.sm,
                      FTDesignTokens.md,
                      FTDesignTokens.lg,
                    ),
                    children: [
                      FTInput(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                        hint: 'Search by title or city',
                        prefixIcon: Icons.search,
                      ),
                      const SizedBox(height: FTDesignTokens.sm),
                      FTCard(
                        child: FTResponsiveTitleAction(
                          title: 'City-first feed',
                          subtitle:
                              'Showing top shortlets around $_selectedCity',
                          action: FTButton(
                            label: _selectedCity,
                            icon: Icons.location_city_outlined,
                            variant: FTButtonVariant.ghost,
                            onPressed: _pickCity,
                          ),
                        ),
                      ),
                      const SizedBox(height: FTDesignTokens.sm),
                      if (rows.isEmpty)
                        FTEmptyState(
                          icon: Icons.home_work_outlined,
                          title: 'No shortlets found',
                          subtitle: _searchCtrl.text.trim().isNotEmpty
                              ? 'No results match your current search.'
                              : 'Try another city or refresh the feed.',
                          primaryCtaText: 'Clear filters',
                          onPrimaryCta: _clearFilters,
                          secondaryCtaText: 'Refresh',
                          onSecondaryCta: _load,
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          cacheExtent: 480,
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: FTDesignTokens.sm),
                          itemBuilder: (_, index) {
                            final row = rows[index];
                            final mediaRows = (row['media'] is List)
                                ? (row['media'] as List)
                                    .whereType<Map>()
                                    .map((v) => Map<String, dynamic>.from(v))
                                    .toList(growable: false)
                                : const <Map<String, dynamic>>[];
                            final image = mediaRows.isNotEmpty
                                ? (mediaRows.first['thumbnail_url'] ??
                                        mediaRows.first['url'] ??
                                        '')
                                    .toString()
                                : (row['image'] ?? row['image_url'] ?? '')
                                    .toString();
                            final views =
                                int.tryParse('${row['views_count'] ?? 0}') ?? 0;
                            final watching = int.tryParse(
                                    '${row['favorites_count'] ?? 0}') ??
                                0;
                            final heatLevel = (row['heat_level'] ?? '')
                                .toString()
                                .trim()
                                .toLowerCase();
                            return InkWell(
                              key: ValueKey<String>(
                                  'shortlet_${row['id'] ?? index}'),
                              borderRadius: BorderRadius.circular(
                                  FTDesignTokens.radiusMd),
                              onTap: () => Navigator.of(context).push(
                                FTRoutes.page(
                                  child: ShortletDetailScreen(shortlet: row),
                                ),
                              ),
                              child: FTCard(
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          FTDesignTokens.radiusSm),
                                      child: SafeImage(
                                        url: image,
                                        width: 110,
                                        height: 98,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: FTDesignTokens.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            formatNaira(
                                              row['nightly_price'] ??
                                                  row['price'],
                                              decimals: 0,
                                            ),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 17,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            (row['title'] ?? 'Shortlet')
                                                .toString(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _location(row),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              FTPill(
                                                text: '$views views',
                                                bgColor:
                                                    scheme.secondaryContainer,
                                                textColor:
                                                    scheme.onSecondaryContainer,
                                              ),
                                              FTPill(
                                                text: '$watching watching',
                                                bgColor:
                                                    scheme.tertiaryContainer,
                                                textColor:
                                                    scheme.onTertiaryContainer,
                                              ),
                                              if (heatLevel == 'hot' ||
                                                  heatLevel == 'hotter')
                                                FTPill(
                                                  text: heatLevel == 'hotter'
                                                      ? 'Hotter'
                                                      : 'Hot',
                                                  bgColor: heatLevel == 'hotter'
                                                      ? scheme.errorContainer
                                                      : scheme.primaryContainer,
                                                  textColor: heatLevel ==
                                                          'hotter'
                                                      ? scheme.onErrorContainer
                                                      : scheme
                                                          .onPrimaryContainer,
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _ShortletSkeleton extends StatelessWidget {
  const _ShortletSkeleton();

  @override
  Widget build(BuildContext context) {
    return FTSkeletonList(
      itemCount: 5,
      itemBuilder: (context, index) => const FTSkeletonCard(height: 96),
    );
  }
}
