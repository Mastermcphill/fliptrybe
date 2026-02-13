import 'package:flutter/material.dart';

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
