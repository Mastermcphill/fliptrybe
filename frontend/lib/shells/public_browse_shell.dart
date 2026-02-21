import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/role_signup_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shortlet_screen.dart';
import '../ui/components/ft_components.dart';
import '../ui/foundation/tokens/ft_radius.dart';
import '../ui/foundation/tokens/ft_spacing.dart';
import '../utils/ft_routes.dart';

class PublicBrowseShell extends StatefulWidget {
  const PublicBrowseShell({
    super.key,
    this.initialIndex = 0,
    this.debugUseLightweightTabs = false,
  });

  final int initialIndex;
  final bool debugUseLightweightTabs;

  @override
  State<PublicBrowseShell> createState() => _PublicBrowseShellState();
}

class _PublicBrowseShellState extends State<PublicBrowseShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
  }

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Public Home'))),
        SizedBox.expand(child: Center(child: Text('Public Marketplace'))),
        SizedBox.expand(child: Center(child: Text('Public Shortlet'))),
        SizedBox.expand(child: Center(child: Text('Public Account'))),
      ];
    }
    return [
      _PublicHome(
        onOpenMarketplace: () => setState(() => _currentIndex = 1),
        onOpenShortlets: () => setState(() => _currentIndex = 2),
      ),
      const MarketplaceScreen(),
      const ShortletScreen(),
      const _GuestAccountTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex > 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: tabs),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (value) => setState(() => _currentIndex = value),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.storefront_outlined),
              label: 'Marketplace',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_work_outlined),
              label: 'Shortlet',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicHome extends StatelessWidget {
  const _PublicHome({
    required this.onOpenMarketplace,
    required this.onOpenShortlets,
  });

  final VoidCallback onOpenMarketplace;
  final VoidCallback onOpenShortlets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FTScaffold(
      appBar: AppBar(title: const Text('Browse FlipTrybe')),
      child: ListView(
        padding: const EdgeInsets.all(FTSpacing.sm),
        children: [
          FTCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Declutter + Shortlet',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: FTSpacing.xs),
                Text(
                  'Browse listings and stays immediately. Login is only required when you want to transact.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: FTSpacing.sm),
          _EntryTile(
            icon: Icons.storefront_outlined,
            title: 'Declutter Marketplace',
            subtitle: 'Browse gadgets, furniture, appliances, and more.',
            onTap: onOpenMarketplace,
          ),
          const SizedBox(height: FTSpacing.xs),
          _EntryTile(
            icon: Icons.home_work_outlined,
            title: 'Shortlet Stays',
            subtitle: 'Explore city-first stays and book when ready.',
            onTap: onOpenShortlets,
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FTCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: FTRadius.roundedMd,
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(FTSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: FTRadius.roundedMd,
            color: Colors.transparent,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.secondaryContainer,
                child: Icon(icon, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(width: FTSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestAccountTab extends StatelessWidget {
  const _GuestAccountTab();

  @override
  Widget build(BuildContext context) {
    return FTScaffold(
      appBar: AppBar(title: const Text('Account')),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(FTSpacing.sm),
            child: FTCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sign in to transact',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: FTSpacing.xs),
                  Text(
                    'Browse is open. Login or create an account to buy, sell, book shortlets, and manage wallet actions.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: FTSpacing.sm),
                  FTButton(
                    label: 'Appearance',
                    icon: Icons.palette_outlined,
                    variant: FTButtonVariant.ghost,
                    expand: true,
                    onPressed: () => Navigator.of(context).push(
                      FTRoutes.page(
                        child: const SettingsScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: FTSpacing.xs),
                  FTButton(
                    label: 'Login',
                    expand: true,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      FTRoutes.slideUp(child: const LoginScreen()),
                    ),
                  ),
                  const SizedBox(height: FTSpacing.xs),
                  FTButton(
                    label: 'Sign up',
                    expand: true,
                    variant: FTButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pushReplacement(
                      FTRoutes.slideUp(child: const RoleSignupScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
