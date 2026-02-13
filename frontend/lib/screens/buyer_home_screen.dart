import 'package:flutter/material.dart';

import '../services/marketplace_catalog_service.dart';
import '../services/marketplace_prefs_service.dart';
import '../services/wallet_service.dart';
import '../ui/components/app_components.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../widgets/listing/listing_card.dart';
import 'listing_detail_screen.dart';
import 'marketplace/marketplace_search_results_screen.dart';
import 'marketplace_screen.dart';
import 'orders_screen.dart';
import 'role_signup_screen.dart';
import 'support_chat_screen.dart';

class BuyerHomeScreen extends StatefulWidget {
  const BuyerHomeScreen({super.key, this.autoLoad = true});

  final bool autoLoad;

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  final _walletService = WalletService();
  final _catalog = MarketplaceCatalogService();
  final _prefs = MarketplacePrefsService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _wallet;
  List<dynamic> _ledger = const [];
  List<Map<String, dynamic>> _all = const [];
  List<Map<String, dynamic>> _dealsRemote = const [];
  List<Map<String, dynamic>> _newDropsRemote = const [];
  Set<int> _favorites = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.autoLoad) {
      _reload();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _walletService.getWallet(),
        _walletService.ledger(),
        _catalog.listAll(),
        _prefs.loadFavorites(),
        _catalog.dealsRemote(limit: 10),
        _catalog.newDropsRemote(limit: 10),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = values[0] as Map<String, dynamic>?;
        _ledger = values[1] as List<dynamic>;
        _all = values[2] as List<Map<String, dynamic>>;
        _favorites = values[3] as Set<int>;
        _dealsRemote = values[4] as List<Map<String, dynamic>>;
        _newDropsRemote = values[5] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load buyer home: $e';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = item['id'] is int
        ? item['id'] as int
        : int.tryParse('${item['id']}') ?? -1;
    if (id <= 0) return;
    final next = <int>{..._favorites};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    setState(() => _favorites = next);
    await _prefs.saveFavorites(next);
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required String seeAllSort,
  }) {
    return Column(
      children: [
        FTSectionHeader(
          title: title,
          subtitle: subtitle,
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MarketplaceSearchResultsScreen(
                  initialQuery: _searchCtrl.text.trim(),
                  initialSort: seeAllSort,
                ),
              ),
            ),
            child: const Text('See all'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 270,
          child: items.isEmpty
              ? const FTCard(
                  child: Center(child: Text('No items in this section yet.')),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, index) {
                    final item = items[index];
                    final id = item['id'] is int
                        ? item['id'] as int
                        : int.tryParse('${item['id']}') ?? -1;
                    return SizedBox(
                      width: 205,
                      child: ListingCard(
                        item: item,
                        isFavorite: _favorites.contains(id),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final txs = _ledger
        .whereType<Map>()
        .take(3)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final recommended = _catalog.recommended(_all, limit: 10);
    final trending = _catalog.trending(_all, limit: 10);
    final newest = _catalog.newest(_all, limit: 10);
    final bestValue = _catalog.bestValue(_all, limit: 10);
    final newDrops = _newDropsRemote.isNotEmpty ? _newDropsRemote : newest;
    final deals = _dealsRemote.isNotEmpty ? _dealsRemote : bestValue;

    return Scaffold(
      body: _loading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                FTSkeleton(height: 46),
                SizedBox(height: 10),
                FTSkeleton(height: 110),
                SizedBox(height: 10),
                FTSkeleton(height: 250),
                SizedBox(height: 10),
                FTSkeleton(height: 250),
              ],
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    floating: true,
                    title: const Text('Buyer Home'),
                    actions: [
                      IconButton(
                          onPressed: _reload, icon: const Icon(Icons.refresh)),
                    ],
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(62),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: TextField(
                          controller: _searchCtrl,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (q) => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MarketplaceSearchResultsScreen(
                                  initialQuery: q),
                            ),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search marketplace',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.tune),
                              tooltip: 'Open search and filters',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MarketplaceSearchResultsScreen(
                                    initialQuery: _searchCtrl.text.trim(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FTErrorState(
                                  message: _error!, onRetry: _reload),
                            ),
                          const FTSectionHeader(
                            title: 'Quick Actions',
                            subtitle: 'Fast access to your core buyer actions',
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _quickAction(
                                icon: Icons.storefront_outlined,
                                label: 'Browse Marketplace',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const MarketplaceScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _quickAction(
                                icon: Icons.receipt_long_outlined,
                                label: 'My Orders',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const OrdersScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              _quickAction(
                                icon: Icons.support_agent_outlined,
                                label: 'Chat Admin',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SupportChatScreen(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _quickAction(
                                icon: Icons.track_changes_outlined,
                                label: 'Track Order',
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const OrdersScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _section(
                            title: 'Recommended for you',
                            subtitle: 'Based on listing quality and relevance',
                            items: recommended,
                            seeAllSort: 'relevance',
                          ),
                          const SizedBox(height: 14),
                          _section(
                            title: 'Trending near you',
                            subtitle: 'Fast-moving listings this week',
                            items: trending,
                            seeAllSort: 'distance',
                          ),
                          const SizedBox(height: 14),
                          _section(
                            title: 'New Drops',
                            subtitle: 'Fresh arrivals across Nigeria',
                            items: newDrops,
                            seeAllSort: 'newest',
                          ),
                          const SizedBox(height: 14),
                          _section(
                            title: 'Hot Deals',
                            subtitle: 'Budget-friendly listings',
                            items: deals,
                            seeAllSort: 'price_low',
                          ),
                          const SizedBox(height: 14),
                          const FTSectionContainer(
                            title: 'How FlipTrybe Protects You',
                            subtitle: 'Escrow and verification flow overview',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Secure escrow for order funds.'),
                                Text('Delivery code + QR confirmation flow.'),
                                Text('Optional inspector verification.'),
                                Text(
                                    'Automatic refund if seller does not respond within 2 hours.'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          FTSectionContainer(
                            title: 'My Wallet Snapshot',
                            subtitle:
                                'Current balance and latest transaction activity',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Current balance: ${formatNaira(_wallet?['balance'])}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                if (txs.isEmpty)
                                  const Text('No recent transactions.')
                                else
                                  ...txs.map((tx) {
                                    final amount = tx['amount'];
                                    final direction =
                                        (tx['direction'] ?? '').toString();
                                    final kind = (tx['kind'] ?? '').toString();
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        direction.toLowerCase() == 'credit'
                                            ? Icons.south_west_outlined
                                            : Icons.north_east_outlined,
                                        color:
                                            direction.toLowerCase() == 'credit'
                                                ? Colors.green
                                                : Colors.redAccent,
                                      ),
                                      title: Text(
                                          kind.isEmpty ? 'Transaction' : kind),
                                      trailing: Text(formatNaira(amount)),
                                    );
                                  }),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          FTSectionContainer(
                            title: 'MoneyBox Awareness',
                            subtitle: 'Role-based access to structured savings',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'MoneyBox is available to Merchants, Drivers and Inspectors. Apply for a role to unlock structured savings bonuses.',
                                ),
                                const SizedBox(height: 10),
                                FTPrimaryButton(
                                  label: 'Apply for Role',
                                  icon: Icons.upgrade_outlined,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RoleSignupScreen(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
