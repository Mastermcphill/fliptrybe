import 'package:flutter/material.dart';

import '../screens/driver_earnings_screen.dart';
import '../screens/driver_home_screen.dart';
import '../screens/driver_jobs_screen.dart';
import '../screens/moneybox_dashboard_screen.dart';
import '../screens/support_chat_screen.dart';

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
        SizedBox.expand(child: Center(child: Text('Driver Jobs'))),
        SizedBox.expand(child: Center(child: Text('Driver Earnings'))),
        SizedBox.expand(child: Center(child: Text('Driver MoneyBox'))),
        SizedBox.expand(child: Center(child: Text('Driver Support'))),
      ];
    }
    return [
      DriverHomeScreen(
          onSelectTab: (index) => setState(() => _currentIndex = index)),
      DriverJobsScreen(),
      const DriverEarningsScreen(),
      const MoneyBoxDashboardScreen(),
      const SupportChatScreen(),
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
                icon: Icon(Icons.local_shipping_outlined), label: 'Jobs'),
            BottomNavigationBarItem(
                icon: Icon(Icons.paid_outlined), label: 'Earnings'),
            BottomNavigationBarItem(
                icon: Icon(Icons.savings_outlined), label: 'MoneyBox'),
            BottomNavigationBarItem(
                icon: Icon(Icons.support_agent_outlined), label: 'Support'),
          ],
        ),
      ),
    );
  }
}
