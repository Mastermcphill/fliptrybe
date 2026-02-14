import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';
import 'ft_app_bar.dart';
import 'ft_network_banner.dart';

class FTScaffold extends StatelessWidget {
  const FTScaffold({
    super.key,
    this.title,
    required this.child,
    this.appBar,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding,
    this.footer,
    this.resizeToAvoidBottomInset,
    this.onRefresh,
    this.showNetworkBanner = true,
  });

  final String? title;
  final Widget child;
  final PreferredSizeWidget? appBar;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry? padding;
  final Widget? footer;
  final bool? resizeToAvoidBottomInset;
  final Future<void> Function()? onRefresh;
  final bool showNetworkBanner;

  @override
  Widget build(BuildContext context) {
    final bodyChild = onRefresh == null
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh!,
            child: child,
          );
    final content = SafeArea(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(AppTokens.s16),
        child: Column(
          children: [
            if (showNetworkBanner) const FTNetworkBanner(),
            Expanded(child: bodyChild),
            if (footer != null) ...[
              const SizedBox(height: AppTokens.s12),
              footer!,
            ],
          ],
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      appBar: appBar ??
          (title != null
              ? FTAppBar(
                  title: title,
                  actions: actions,
                  leading: leading,
                )
              : null),
      body: content,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
