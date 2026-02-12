import 'package:flutter/material.dart';

import '../screens/create_listing_screen.dart';
import '../screens/growth/growth_analytics_screen.dart';
import '../screens/merchant_home_screen.dart';
import '../screens/merchant_listings_screen.dart';
import '../screens/merchant_orders_screen.dart';
import '../screens/support_chat_screen.dart';

class MerchantShell extends StatefulWidget {
  const MerchantShell({super.key, this.debugUseLightweightTabs = false});

  final bool debugUseLightweightTabs;

  @override
  State<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends State<MerchantShell> {
  int _currentIndex = 0;

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Merchant Home'))),
        SizedBox.expand(child: Center(child: Text('Merchant Listings'))),
        SizedBox.expand(child: Center(child: Text('Merchant Orders'))),
        SizedBox.expand(child: Center(child: Text('Merchant Growth'))),
        SizedBox.expand(child: Center(child: Text('Merchant Support'))),
      ];
    }
    return [
      MerchantHomeScreen(onSelectTab: (i) => setState(() => _currentIndex = i)),
      const MerchantListingsScreen(),
      const MerchantOrdersScreen(),
      const GrowthAnalyticsScreen(role: 'merchant'),
      const SupportChatScreen(),
    ];
  }

  void _openCreateListing() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateListingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final showCreateFab = !widget.debugUseLightweightTabs &&
        (_currentIndex == 0 || _currentIndex == 1);

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex > 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: tabs,
        ),
        floatingActionButton: showCreateFab
            ? FloatingActionButton.extended(
                onPressed: _openCreateListing,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Create listing'),
              )
            : null,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (value) => setState(() => _currentIndex = value),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2_outlined), label: 'Listings'),
            BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            BottomNavigationBarItem(
                icon: Icon(Icons.trending_up_outlined), label: 'Growth'),
            BottomNavigationBarItem(
                icon: Icon(Icons.support_agent_outlined), label: 'Support'),
          ],
        ),
      ),
    );
  }
}
