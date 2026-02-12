import 'package:flutter/material.dart';

import '../screens/inspector_bookings_screen.dart';
import '../screens/inspector_earnings_screen.dart';
import '../screens/inspector_home_screen.dart';
import '../screens/moneybox_dashboard_screen.dart';
import '../screens/support_chat_screen.dart';

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
        SizedBox.expand(child: Center(child: Text('Inspector Earnings'))),
        SizedBox.expand(child: Center(child: Text('Inspector MoneyBox'))),
        SizedBox.expand(child: Center(child: Text('Inspector Support'))),
      ];
    }
    return [
      InspectorHomeScreen(
          onSelectTab: (index) => setState(() => _currentIndex = index)),
      InspectorBookingsScreen(),
      const InspectorEarningsScreen(),
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
                icon: Icon(Icons.assignment_outlined), label: 'Bookings'),
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
