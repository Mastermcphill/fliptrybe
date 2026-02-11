import 'package:flutter/material.dart';

import '../screens/inspector_bookings_screen.dart';
import '../screens/inspector_growth_screen.dart';
import '../screens/inspector_home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/wallet_screen.dart';

class InspectorShell extends StatefulWidget {
  const InspectorShell({super.key, this.debugUseLightweightTabs = false});

  final bool debugUseLightweightTabs;

  @override
  State<InspectorShell> createState() => _InspectorShellState();
}

class _InspectorShellState extends State<InspectorShell> {
  int _currentIndex = 0;

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Inspector Home'))),
        SizedBox.expand(child: Center(child: Text('Inspector Bookings'))),
        SizedBox.expand(child: Center(child: Text('Inspector Wallet'))),
        SizedBox.expand(child: Center(child: Text('Inspector Growth'))),
        SizedBox.expand(child: Center(child: Text('Inspector Profile'))),
      ];
    }
    return const [
      InspectorHomeScreen(),
      InspectorBookingsScreen(),
      WalletScreen(),
      InspectorGrowthScreen(),
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
        body: IndexedStack(
          index: _currentIndex,
          children: tabs,
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (value) => setState(() => _currentIndex = value),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.assignment_outlined), label: 'Bookings'),
            BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: 'Wallet'),
            BottomNavigationBarItem(
                icon: Icon(Icons.trending_up_outlined), label: 'Growth'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
