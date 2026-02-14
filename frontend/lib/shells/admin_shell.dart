import 'package:flutter/material.dart';

import '../screens/admin_autopilot_screen.dart';
import '../screens/admin_hub_screen.dart';
import '../screens/admin_notify_queue_screen.dart';
import '../screens/admin_overview_screen.dart';
import '../screens/admin_support_threads_screen.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, this.debugUseLightweightTabs = false});

  final bool debugUseLightweightTabs;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _currentIndex = 0;

  List<Widget> _tabs() {
    if (widget.debugUseLightweightTabs) {
      return const [
        SizedBox.expand(child: Center(child: Text('Admin Overview'))),
        SizedBox.expand(child: Center(child: Text('Admin Operations'))),
        SizedBox.expand(child: Center(child: Text('Admin Queue'))),
        SizedBox.expand(child: Center(child: Text('Admin Support'))),
        SizedBox.expand(child: Center(child: Text('Admin Settings'))),
      ];
    }
    return const [
      AdminOverviewScreen(),
      AdminHubScreen(),
      AdminNotifyQueueScreen(),
      AdminSupportThreadsScreen(),
      AdminAutopilotScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final isWide = MediaQuery.of(context).size.width >= 1000;
    const destinations = [
      NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined), label: Text('Overview')),
      NavigationRailDestination(
          icon: Icon(Icons.settings_applications_outlined),
          label: Text('Operations')),
      NavigationRailDestination(
          icon: Icon(Icons.queue_outlined), label: Text('Queue')),
      NavigationRailDestination(
          icon: Icon(Icons.support_agent_outlined), label: Text('Support')),
      NavigationRailDestination(
          icon: Icon(Icons.tune_outlined), label: Text('Settings')),
    ];
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex > 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: isWide
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _currentIndex,
                    onDestinationSelected: (value) =>
                        setState(() => _currentIndex = value),
                    labelType: NavigationRailLabelType.all,
                    destinations: destinations,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: IndexedStack(index: _currentIndex, children: tabs),
                  ),
                ],
              )
            : IndexedStack(index: _currentIndex, children: tabs),
        bottomNavigationBar: isWide
            ? null
            : BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (value) => setState(() => _currentIndex = value),
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.dashboard_outlined), label: 'Overview'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.settings_applications_outlined),
                      label: 'Operations'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.queue_outlined), label: 'Queue'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.support_agent_outlined),
                      label: 'Support'),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.tune_outlined), label: 'Settings'),
                ],
              ),
      ),
    );
  }
}
