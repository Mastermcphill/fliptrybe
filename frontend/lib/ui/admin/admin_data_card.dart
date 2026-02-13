import 'package:flutter/material.dart';

import '../components/ft_components.dart';
import '../foundation/app_tokens.dart';

class AdminDataCard extends StatelessWidget {
  const AdminDataCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTSectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
          ),
          const SizedBox(height: AppTokens.s12),
          child,
        ],
      ),
    );
  }
}
