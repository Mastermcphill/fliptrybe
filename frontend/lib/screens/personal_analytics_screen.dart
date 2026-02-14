import 'package:flutter/material.dart';

import '../services/growth_analytics_service.dart';
import '../ui/components/ft_components.dart';
import '../utils/formatters.dart';
import '../utils/ui_feedback.dart';

class PersonalAnalyticsScreen extends StatefulWidget {
  const PersonalAnalyticsScreen({super.key, required this.role});

  final String role;

  @override
  State<PersonalAnalyticsScreen> createState() =>
      _PersonalAnalyticsScreenState();
}

class _PersonalAnalyticsScreenState extends State<PersonalAnalyticsScreen> {
  final GrowthAnalyticsService _service = GrowthAnalyticsService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _payload = const <String, dynamic>{};

  bool get _isMerchant => widget.role.toLowerCase() == 'merchant';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _isMerchant
          ? await _service.merchantAnalytics()
          : await _service.buyerAnalytics();
      if (!mounted) return;
      setState(() {
        _payload = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UIFeedback.mapDioErrorToMessage(e);
        _loading = false;
      });
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? 0}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: _isMerchant ? 'Merchant Analytics' : 'Buyer Analytics',
      onRefresh: _load,
      child: FTLoadStateLayout(
        loading: _loading,
        error: _error,
        onRetry: _load,
        empty: false,
        loadingState: FTSkeletonList(
          itemCount: 4,
          itemBuilder: (context, index) => const FTSkeletonCard(height: 92),
        ),
        emptyState: const SizedBox.shrink(),
        child: _isMerchant ? _buildMerchant(context) : _buildBuyer(context),
      ),
    );
  }

  Widget _buildBuyer(BuildContext context) {
    final totalPurchases = _asInt(_payload['total_purchases']);
    final totalSpentMinor = _asInt(_payload['total_spent_minor']);
    final savedListings = _asInt(_payload['saved_listings_count']);
    return ListView(
      children: [
        FTSection(
          title: 'Purchase Overview',
          subtitle: 'Your buying activity and spend profile.',
          child: Column(
            children: [
              FTMetricTile(
                label: 'Total purchases',
                value: '$totalPurchases',
                icon: Icons.shopping_bag_outlined,
              ),
              const SizedBox(height: 8),
              FTMetricTile(
                label: 'Total spent',
                value: formatNaira(totalSpentMinor / 100),
                icon: Icons.payments_outlined,
              ),
              const SizedBox(height: 8),
              FTMetricTile(
                label: 'Saved listings',
                value: '$savedListings',
                icon: Icons.favorite_border,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMerchant(BuildContext context) {
    final totalSales = _asInt(_payload['total_sales']);
    final commissionPaidMinor = _asInt(_payload['commission_paid_minor']);
    final netEarningsMinor = _asInt(_payload['net_earnings_minor']);
    final conversionRate =
        double.tryParse('${_payload['conversion_rate'] ?? 0}') ?? 0;
    return ListView(
      children: [
        FTSection(
          title: 'Merchant Performance',
          subtitle: 'Sales, commission and conversion metrics.',
          child: Column(
            children: [
              FTMetricTile(
                label: 'Total sales',
                value: '$totalSales',
                icon: Icons.point_of_sale_outlined,
              ),
              const SizedBox(height: 8),
              FTMetricTile(
                label: 'Commission paid',
                value: formatNaira(commissionPaidMinor / 100),
                icon: Icons.account_balance_outlined,
              ),
              const SizedBox(height: 8),
              FTMetricTile(
                label: 'Net earnings',
                value: formatNaira(netEarningsMinor / 100),
                icon: Icons.trending_up_outlined,
              ),
              const SizedBox(height: 8),
              FTMetricTile(
                label: 'Conversion rate',
                value: '${conversionRate.toStringAsFixed(2)}%',
                subtitle: 'Views to paid orders',
                icon: Icons.show_chart_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
