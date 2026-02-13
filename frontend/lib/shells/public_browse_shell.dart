import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/role_signup_screen.dart';
import '../screens/shortlet_screen.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Browse FlipTrybe')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Declutter + Shortlet',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 6),
                Text(
                  'Browse listings and stays immediately. Login is only required when you want to transact.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _EntryTile(
            icon: Icons.storefront_outlined,
            title: 'Declutter Marketplace',
            subtitle: 'Browse gadgets, furniture, appliances, and more.',
            onTap: onOpenMarketplace,
          ),
          const SizedBox(height: 10),
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
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFF1F5F9),
              child: Icon(icon, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _GuestAccountTab extends StatelessWidget {
  const _GuestAccountTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sign in to transact',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Browse is open. Login or create an account to buy, sell, book shortlets, and manage wallet actions.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        ),
                        child: const Text('Login'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RoleSignupScreen()),
                        ),
                        child: const Text('Sign up'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
