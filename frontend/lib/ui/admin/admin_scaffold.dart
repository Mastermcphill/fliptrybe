import 'package:flutter/material.dart';

import '../../screens/settings_demo_screen.dart';
import '../../utils/auth_navigation.dart';
import '../components/ft_app_bar.dart';
import '../foundation/app_tokens.dart';

class AdminScaffold extends StatelessWidget {
  const AdminScaffold({
    super.key,
    required this.title,
    this.child,
    this.body,
    this.actions,
    this.onRefresh,
    this.padding,
  }) : assert(
          child != null || body != null,
          'Either child or body must be provided.',
        );

  final String title;
  final Widget? child;
  final Widget? body;
  final List<Widget>? actions;
  final VoidCallback? onRefresh;
  final EdgeInsetsGeometry? padding;

  Future<void> _handleMenuAction(
    BuildContext context,
    _AdminMenuAction action,
  ) async {
    if (!context.mounted) return;
    switch (action) {
      case _AdminMenuAction.appearance:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsDemoScreen()),
        );
        return;
      case _AdminMenuAction.signOut:
        await logoutToLanding(context);
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 1000;

    return Scaffold(
      appBar: FTAppBar(
        title: title,
        actions: [
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ...?actions,
          PopupMenuButton<_AdminMenuAction>(
            tooltip: 'Admin menu',
            onSelected: (value) => _handleMenuAction(context, value),
            itemBuilder: (context) => [
              const PopupMenuItem<_AdminMenuAction>(
                value: _AdminMenuAction.appearance,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Appearance'),
                ),
              ),
              PopupMenuItem<_AdminMenuAction>(
                value: _AdminMenuAction.signOut,
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.logout, color: scheme.error),
                  title:
                      Text('Sign out', style: TextStyle(color: scheme.error)),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        color: scheme.surface,
        child: SafeArea(
          child: Padding(
            padding: padding ??
                EdgeInsets.symmetric(
                  horizontal: isWide ? AppTokens.s24 : AppTokens.s16,
                  vertical: AppTokens.s16,
                ),
            child: body ?? child!,
          ),
        ),
      ),
    );
  }
}

enum _AdminMenuAction { appearance, signOut }
