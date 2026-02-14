import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../ui/components/ft_components.dart';
import '../ui/design/ft_tokens.dart';
import '../utils/formatters.dart';
import 'web_meta.dart';

enum _MarketingPage {
  home,
  howItWorks,
  merchants,
  shortlets,
  earn,
  calculator,
  investors,
}

class PublicMarketingSite extends StatefulWidget {
  const PublicMarketingSite({
    super.key,
    required this.initialPath,
    required this.onLogin,
    required this.onSignup,
  });

  final String initialPath;
  final VoidCallback onLogin;
  final VoidCallback onSignup;

  static bool isMarketingPath(String path) {
    final clean = path.trim().toLowerCase();
    return const <String>{
      '/',
      '/how-it-works',
      '/for-merchants',
      '/for-shortlets',
      '/earn-with-fliptrybe',
      '/growth-calculator',
      '/investors',
    }.contains(clean);
  }

  @override
  State<PublicMarketingSite> createState() => _PublicMarketingSiteState();
}

class _PublicMarketingSiteState extends State<PublicMarketingSite> {
  _MarketingPage _page = _MarketingPage.home;
  double _monthlyTransactions = 120;
  double _averageOrderMinor = 4500000; // 45,000 NGN in minor units.

  @override
  void initState() {
    super.initState();
    _page = _pageFromPath(widget.initialPath);
    _syncPageMetaAndPath();
  }

  _MarketingPage _pageFromPath(String path) {
    switch (path.trim().toLowerCase()) {
      case '/how-it-works':
        return _MarketingPage.howItWorks;
      case '/for-merchants':
        return _MarketingPage.merchants;
      case '/for-shortlets':
        return _MarketingPage.shortlets;
      case '/earn-with-fliptrybe':
        return _MarketingPage.earn;
      case '/growth-calculator':
        return _MarketingPage.calculator;
      case '/investors':
        return _MarketingPage.investors;
      default:
        return _MarketingPage.home;
    }
  }

  String _pathForPage(_MarketingPage page) {
    switch (page) {
      case _MarketingPage.home:
        return '/';
      case _MarketingPage.howItWorks:
        return '/how-it-works';
      case _MarketingPage.merchants:
        return '/for-merchants';
      case _MarketingPage.shortlets:
        return '/for-shortlets';
      case _MarketingPage.earn:
        return '/earn-with-fliptrybe';
      case _MarketingPage.calculator:
        return '/growth-calculator';
      case _MarketingPage.investors:
        return '/investors';
    }
  }

  void _setPage(_MarketingPage page) {
    if (_page == page) return;
    setState(() => _page = page);
    _syncPageMetaAndPath();
  }

  void _syncPageMetaAndPath() {
    setWebPath(_pathForPage(_page));
    switch (_page) {
      case _MarketingPage.home:
        setWebMeta(
          title: 'FlipTrybe - Declutter Marketplace + Shortlet Stays',
          description:
              'Buy, sell, host and grow on FlipTrybe with transparent 5% commissions and trust-first commerce.',
        );
        break;
      case _MarketingPage.howItWorks:
        setWebMeta(
          title: 'How FlipTrybe Works',
          description:
              'List, connect and earn in three deterministic steps across marketplace and shortlet rails.',
        );
        break;
      case _MarketingPage.merchants:
        setWebMeta(
          title: 'For Merchants - FlipTrybe',
          description:
              'Scale merchant sales with city-first discovery, referral growth loops, and predictable settlement.',
        );
        break;
      case _MarketingPage.shortlets:
        setWebMeta(
          title: 'For Shortlet Hosts - FlipTrybe',
          description:
              'Host shortlet stays with secure payments, trust signals and conversion-ready discovery.',
        );
        break;
      case _MarketingPage.earn:
        setWebMeta(
          title: 'Earn With FlipTrybe',
          description:
              'Merchants, drivers and inspectors earn via operationally safe rails and transparent payouts.',
        );
        break;
      case _MarketingPage.calculator:
        setWebMeta(
          title: 'FlipTrybe Growth Calculator',
          description:
              'Estimate GMV and commission projections from transaction volume and average order value.',
        );
        break;
      case _MarketingPage.investors:
        setWebMeta(
          title: 'FlipTrybe Investors',
          description:
              'Investor overview for GMV, revenue model and unit economics foundations.',
        );
        break;
    }
  }

  Widget _navItem(String label, _MarketingPage page) {
    final selected = _page == page;
    return TextButton(
      onPressed: () => _setPage(page),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }

  Widget _hero() {
    return FTSection(
      title: 'Declutter Marketplace + Shortlet Stays',
      subtitle:
          'Launch and grow your commerce journey with deterministic trust rails.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: FTDesignTokens.sm,
            runSpacing: FTDesignTokens.sm,
            children: [
              FTPrimaryButton(
                label: 'Start Buying',
                icon: Icons.shopping_bag_outlined,
                onPressed: widget.onSignup,
              ),
              FTSecondaryButton(
                label: 'Become a Merchant',
                icon: Icons.storefront_outlined,
                onPressed: widget.onSignup,
              ),
            ],
          ),
          const SizedBox(height: FTDesignTokens.md),
          FTCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Commission transparency',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: FTDesignTokens.xs),
                Text(
                  'FlipTrybe applies a clear 5% commission model for declutter and shortlet transactions.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _howItWorks() {
    return const FTSection(
      title: 'How it works',
      subtitle: 'List -> Connect -> Earn',
      child: Column(
        children: [
          FTListTile(
            leading: Icon(Icons.add_business_outlined),
            title: '1. List',
            subtitle: 'Publish marketplace items or shortlet properties.',
          ),
          FTListTile(
            leading: Icon(Icons.people_alt_outlined),
            title: '2. Connect',
            subtitle: 'Reach buyers and renters via city-first discovery.',
          ),
          FTListTile(
            leading: Icon(Icons.account_balance_wallet_outlined),
            title: '3. Earn',
            subtitle: 'Get paid through wallet, Paystack, or manual rails.',
          ),
        ],
      ),
    );
  }

  Widget _testimonialsFaqFooter() {
    const faqs = <Map<String, String>>[
      {
        'q': 'How much commission does FlipTrybe charge?',
        'a': 'A transparent 5% model applies to eligible transactions.'
      },
      {
        'q': 'Can I browse without creating an account?',
        'a':
            'Yes. Marketplace and shortlet discovery are available before login.'
      },
      {
        'q': 'When does referral reward unlock?',
        'a':
            'When the referred user completes a first successful paid transaction.'
      },
    ];

    return Column(
      children: [
        const FTSection(
          title: 'Testimonials',
          subtitle: 'Customer stories are being compiled.',
          child: FTEmptyState(
            icon: Icons.rate_review_outlined,
            title: 'Testimonials coming soon',
            subtitle: 'This block is ready for production testimonials.',
          ),
        ),
        const SizedBox(height: FTDesignTokens.md),
        FTSection(
          title: 'FAQ',
          child: Column(
            children: faqs
                .map(
                  (item) => ExpansionTile(
                    title: Text(item['q'] ?? ''),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(item['a'] ?? ''),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: FTDesignTokens.md),
        FTCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Terms | Privacy | Contact',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: FTDesignTokens.xs),
              Text(
                'Version ${ApiConfig.appVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _growthCalculator() {
    final gmvMinor = (_monthlyTransactions * _averageOrderMinor).round();
    final commissionMinor = (gmvMinor * 0.05).round();
    return ListView(
      children: [
        FTSection(
          title: 'Growth Calculator',
          subtitle: 'Projection uses real 5% commission logic.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Monthly transactions: ${_monthlyTransactions.round()}'),
              Slider(
                value: _monthlyTransactions,
                min: 10,
                max: 5000,
                divisions: 499,
                label: _monthlyTransactions.round().toString(),
                onChanged: (value) =>
                    setState(() => _monthlyTransactions = value),
              ),
              Text(
                  'Average order value: ${formatNaira(_averageOrderMinor / 100)}'),
              Slider(
                value: _averageOrderMinor,
                min: 100000,
                max: 50000000,
                divisions: 499,
                label: formatNaira(_averageOrderMinor / 100, decimals: 0),
                onChanged: (value) =>
                    setState(() => _averageOrderMinor = value),
              ),
              const SizedBox(height: FTDesignTokens.sm),
              FTMetricTile(
                label: 'Projected GMV',
                value: formatNaira(gmvMinor / 100),
              ),
              const SizedBox(height: FTDesignTokens.sm),
              FTMetricTile(
                label: 'Projected Commission (5%)',
                value: formatNaira(commissionMinor / 100),
              ),
            ],
          ),
        ),
        _testimonialsFaqFooter(),
      ],
    );
  }

  Widget _investorsPage() {
    return ListView(
      children: [
        FTSection(
          title: 'Investor Snapshot',
          subtitle:
              'FlipTrybe combines commerce demand, shortlet supply, and audited settlement rails.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FTListTile(
                leading: Icon(Icons.show_chart_outlined),
                title: 'GMV trend visibility',
                subtitle: 'Investor dashboard reports platform GMV trajectory.',
              ),
              const FTListTile(
                leading: Icon(Icons.monetization_on_outlined),
                title: 'Commission model clarity',
                subtitle:
                    '5% base model with deterministic ledger-backed settlement.',
              ),
              const FTListTile(
                leading: Icon(Icons.insights_outlined),
                title: 'Unit economics access',
                subtitle:
                    'Average order value, commission per order, CAC and LTV estimate.',
              ),
              const SizedBox(height: FTDesignTokens.sm),
              FTPrimaryButton(
                label: 'Login to investor dashboard',
                icon: Icons.analytics_outlined,
                onPressed: widget.onLogin,
              ),
            ],
          ),
        ),
        _testimonialsFaqFooter(),
      ],
    );
  }

  Widget _pageBody() {
    switch (_page) {
      case _MarketingPage.home:
        return ListView(
          children: [
            _hero(),
            const SizedBox(height: FTDesignTokens.md),
            _howItWorks(),
            _testimonialsFaqFooter(),
          ],
        );
      case _MarketingPage.howItWorks:
        return ListView(children: [_howItWorks(), _testimonialsFaqFooter()]);
      case _MarketingPage.merchants:
        return ListView(
          children: [
            const FTSection(
              title: 'For Merchants',
              subtitle:
                  'Launch inventory and convert demand with discovery, trust rails, and payout controls.',
              child: FTListTile(
                leading: Icon(Icons.storefront_outlined),
                title: 'Merchant growth surface',
                subtitle:
                    'Marketplace feeds, saved searches, and analytics-backed operations.',
              ),
            ),
            _testimonialsFaqFooter(),
          ],
        );
      case _MarketingPage.shortlets:
        return ListView(
          children: [
            const FTSection(
              title: 'For Shortlet Hosts',
              subtitle:
                  'Host city-first stays with operational trust and secure checkout rails.',
              child: FTListTile(
                leading: Icon(Icons.home_work_outlined),
                title: 'Host confidence',
                subtitle:
                    'Shortlet recommendations, media quality signals, and payment options.',
              ),
            ),
            _testimonialsFaqFooter(),
          ],
        );
      case _MarketingPage.earn:
        return ListView(
          children: [
            const FTSection(
              title: 'Earn with FlipTrybe',
              subtitle:
                  'Merchant, driver and inspector earnings with transparent rails and compliance controls.',
              child: FTListTile(
                leading: Icon(Icons.paid_outlined),
                title: 'Deterministic payouts',
                subtitle:
                    'Track wallet credits, withdrawals and autosave behavior in one flow.',
              ),
            ),
            _testimonialsFaqFooter(),
          ],
        );
      case _MarketingPage.calculator:
        return _growthCalculator();
      case _MarketingPage.investors:
        return _investorsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      title: 'FlipTrybe',
      padding: const EdgeInsets.all(FTDesignTokens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FTCard(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _navItem('Home', _MarketingPage.home),
                _navItem('How it works', _MarketingPage.howItWorks),
                _navItem('For merchants', _MarketingPage.merchants),
                _navItem('For shortlets', _MarketingPage.shortlets),
                _navItem('Earn', _MarketingPage.earn),
                _navItem('Growth calculator', _MarketingPage.calculator),
                _navItem('Investors', _MarketingPage.investors),
                const SizedBox(width: 12),
                FTButton(
                  label: 'Login',
                  variant: FTButtonVariant.ghost,
                  onPressed: widget.onLogin,
                ),
                FTButton(
                  label: 'Sign up',
                  onPressed: widget.onSignup,
                ),
              ],
            ),
          ),
          const SizedBox(height: FTDesignTokens.md),
          Expanded(child: _pageBody()),
        ],
      ),
    );
  }
}
