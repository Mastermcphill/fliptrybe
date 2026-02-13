import 'package:flutter/material.dart';

import '../screens/driver_home_screen.dart';
import '../screens/driver_jobs_screen.dart';
import '../screens/marketplace_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/shortlet_screen.dart';

class DriverShell extends StatefulWidget {
  const DriverShell({super.key, this.debugUseLightweightTabs = false});

  final bool debugUseLightweightTabs;

  @override
  State<DriverShell> createState() => _DriverShellState();
}

class _DriverShellState extends State<DriverShell> {
  int _currentIndex = 0;

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Driver Home'))),
        SizedBox.expand(child: Center(child: Text('Driver Marketplace'))),
        SizedBox.expand(child: Center(child: Text('Driver Shortlet'))),
        SizedBox.expand(child: Center(child: Text('Driver Orders'))),
        SizedBox.expand(child: Center(child: Text('Driver Profile'))),
      ];
    }
    return [
      DriverHomeScreen(
          onSelectTab: (index) => setState(() => _currentIndex = index)),
      const MarketplaceScreen(),
      const ShortletScreen(),
      DriverJobsScreen(),
      const ProfileScreen(),
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
                icon: Icon(Icons.storefront_outlined), label: 'Marketplace'),
            BottomNavigationBarItem(
                icon: Icon(Icons.home_work_outlined), label: 'Shortlet'),
            BottomNavigationBarItem(
                icon: Icon(Icons.local_shipping_outlined), label: 'Orders'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
