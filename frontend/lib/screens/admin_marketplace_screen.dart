import 'package:flutter/material.dart';

import '../constants/ng_states.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import '../utils/auth_navigation.dart';
import '../utils/ft_routes.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';
import 'admin_autopilot_screen.dart';

class AdminMarketplaceScreen extends StatefulWidget {
  const AdminMarketplaceScreen({super.key});

  @override
  State<AdminMarketplaceScreen> createState() => _AdminMarketplaceScreenState();
}

class _AdminMarketplaceScreenState extends State<AdminMarketplaceScreen> {
  final _qCtrl = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String _state = allNigeriaLabel;
  String _status = 'all';
  String _sort = 'newest';
  String _category = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoading = true}) async {
    setState(() {
      if (showLoading) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });
    try {
      final query = <String, String>{
        'limit': '100',
        'sort': _sort,
      };
      if (_qCtrl.text.trim().isNotEmpty) query['q'] = _qCtrl.text.trim();
      if (_state != allNigeriaLabel) query['state'] = _state;
      if (_status != 'all') query['status'] = _status;
      if (_category.trim().isNotEmpty) query['category'] = _category.trim();
      final uri = Uri(path: '/admin/listings/search', queryParameters: query);
      final data =
          await ApiClient.instance.getJson(ApiConfig.api(uri.toString()));
      if (!mounted) return;
      final rows = (data is Map && data['items'] is List)
          ? data['items'] as List
          : <dynamic>[];
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((raw) => Map<String, dynamic>.from(raw))
            .toList(growable: false);
        _loading = false;
        _refreshing = false;
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
        _refreshing = false;
        _error = errorMessage;
      });
      UIFeedback.showErrorSnack(context, errorMessage);
    }
  }

  void _showDetails(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text((item['title'] ?? 'Listing').toString()),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Listing ID: ${(item['id'] ?? '').toString()}'),
              Text('Price: ${formatNaira(item['price'])}'),
              Text('State: ${(item['state'] ?? '').toString()}'),
              Text('City: ${(item['city'] ?? '').toString()}'),
              Text('Category: ${(item['category'] ?? '').toString()}'),
              Text('Status: ${(item['status'] ?? '').toString()}'),
              const SizedBox(height: 8),
              const Text('Seller',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Text('ID: ${(item['merchant_id'] ?? '').toString()}'),
              Text(
                  'Name: ${(item['merchant'] is Map ? item['merchant']['name'] : '').toString()}'),
              Text(
                  'Email: ${(item['merchant'] is Map ? item['merchant']['email'] : '').toString()}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      FTRoutes.page(child: const AdminAutopilotScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'Admin Marketplace',
      actions: [
        IconButton(
          onPressed: () => _load(showLoading: _items.isEmpty),
          icon: const Icon(Icons.refresh),
        )
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                FTTextField(
                  controller: _qCtrl,
                  labelText: 'Search listings or merchant',
                  prefixIcon: Icons.search,
                  onSubmitted: (_) => _load(showLoading: _items.isEmpty),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FTDropDownField<String>(
                        initialValue: _status,
                        labelText: 'Status',
                        items: const [
                          DropdownMenuItem(
                              value: 'all', child: Text('All Status')),
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'inactive', child: Text('Inactive')),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FTDropDownField<String>(
                        initialValue: _sort,
                        labelText: 'Sort',
                        items: const [
                          DropdownMenuItem(
                              value: 'newest', child: Text('Newest')),
                          DropdownMenuItem(
                              value: 'price_asc',
                              child: Text('Price Low to High')),
                          DropdownMenuItem(
                              value: 'price_desc',
                              child: Text('Price High to Low')),
                        ],
                        onChanged: (v) => setState(() => _sort = v ?? 'newest'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FTDropDownField<String>(
                        initialValue: _state,
                        labelText: 'State',
                        isExpanded: true,
                        items: <String>[allNigeriaLabel, ...nigeriaStates]
                            .map((state) => DropdownMenuItem(
                                  value: state,
                                  child: Text(state == allNigeriaLabel
                                      ? state
                                      : displayState(state)),
                                ))
                            .toList(growable: false),
                        onChanged: (v) =>
                            setState(() => _state = v ?? allNigeriaLabel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FTTextField(
                        labelText: 'Category',
                        onChanged: (v) => _category = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FTButton(
                      label: 'Apply',
                      onPressed: () => _load(showLoading: _items.isEmpty),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: FTLoadStateLayout(
              loading: _loading,
              error: _items.isEmpty ? _error : null,
              onRetry: () => _load(showLoading: _items.isEmpty),
              empty: _items.isEmpty,
              loadingState: ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  FTSkeletonCard(height: 92),
                  FTSkeletonCard(height: 92),
                  FTSkeletonCard(height: 92),
                ],
              ),
              emptyState: FTEmptyState(
                icon: Icons.storefront_outlined,
                title: 'No listings found',
                subtitle: 'Adjust search text or filters and try again.',
                primaryCtaText: 'Refresh',
                onPrimaryCta: () => _load(showLoading: true),
                secondaryCtaText: 'Go to Settings',
                onSecondaryCta: _openSettings,
              ),
              child: ListView.separated(
                cacheExtent: 720,
                itemCount: _items.length + (_error == null ? 0 : 1),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  if (_error != null && index == 0) {
                    return FTCard(
                      child: FTResponsiveTitleAction(
                        title: 'Could not refresh admin listings',
                        subtitle: _error!,
                        action: FTButton(
                          label: _refreshing ? 'Refreshing...' : 'Retry',
                          icon: Icons.refresh,
                          variant: FTButtonVariant.ghost,
                          onPressed: _refreshing
                              ? null
                              : () => _load(showLoading: false),
                        ),
                      ),
                    );
                  }
                  final itemIndex = _error == null ? index : index - 1;
                  final item = _items[itemIndex];
                  final title = (item['title'] ?? 'Listing').toString();
                  final merchantName = (item['merchant'] is Map)
                      ? (item['merchant']['name'] ?? '').toString()
                      : '';
                  final state = (item['state'] ?? '').toString();
                  final city = (item['city'] ?? '').toString();
                  final location = [city, state]
                      .where((value) => value.trim().isNotEmpty)
                      .join(', ');
                  final price = formatNaira(item['price']);
                  return ListTile(
                    key: ValueKey<String>(
                        'admin_listing_${item['id'] ?? itemIndex}'),
                    title: Text(title),
                    subtitle: Text(
                      '$price • ${location.isEmpty ? "Location not set" : location}\nSeller: $merchantName',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.open_in_new_outlined),
                    onTap: () => _showDetails(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
