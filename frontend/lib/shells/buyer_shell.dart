import 'package:flutter/material.dart';

import '../screens/buyer_home_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/orders_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/support_chat_screen.dart';

class BuyerShell extends StatefulWidget {
  const BuyerShell({super.key, this.debugUseLightweightTabs = false});

  final bool debugUseLightweightTabs;

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> {
  int _currentIndex = 0;

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Buyer Home'))),
        SizedBox.expand(child: Center(child: Text('Buyer Marketplace'))),
        SizedBox.expand(child: Center(child: Text('Buyer Orders'))),
        SizedBox.expand(child: Center(child: Text('Buyer Support'))),
        SizedBox.expand(child: Center(child: Text('Buyer Profile'))),
      ];
    }
    return const [
      BuyerHomeScreen(),
      MarketplaceScreen(),
      OrdersScreen(),
      SupportChatScreen(),
      ProfileScreen(),
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
                icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.storefront_outlined), label: 'Marketplace'),
            BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined), label: 'Orders'),
            BottomNavigationBarItem(
                icon: Icon(Icons.support_agent_outlined), label: 'Support'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
