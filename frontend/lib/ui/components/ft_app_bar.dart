import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';
import '../foundation/app_typography.dart';

class FTAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FTAppBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.showDivider = true,
    this.centerTitle = false,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showDivider;
  final bool centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      title: title == null
          ? null
          : Text(
              title!,
              style: AppTypography.sectionTitle(context),
            ),
      leading: leading,
      actions: actions,
      centerTitle: centerTitle,
      bottom: showDivider
          ? PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant,
              ),
            )
          : null,
      toolbarHeight: kToolbarHeight,
      surfaceTintColor: Colors.transparent,
      titleSpacing: AppTokens.s16,
    );
  }
}
