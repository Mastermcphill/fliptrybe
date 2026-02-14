import 'package:flutter/material.dart';

import 'ft_tile.dart';

class FTListTile extends StatelessWidget {
  const FTListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.badgeText,
    this.onTap,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? badgeText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FTTile(
      leadingWidget: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: (subtitle ?? '').trim().isEmpty
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: trailing,
      badgeText: badgeText,
      onTap: onTap,
    );
  }
}
