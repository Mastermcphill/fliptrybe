import 'package:flutter/material.dart';

import '../theme/ft_tokens.dart';

class FTScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final FloatingActionButton? floatingActionButton;

  const FTScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FTTokens.bg,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      body: SafeArea(child: child),
      floatingActionButton: floatingActionButton,
    );
  }
}

class FTCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const FTCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? FTTokens.card,
        borderRadius: BorderRadius.circular(FTTokens.radiusMd),
        boxShadow: FTTokens.shadowSm,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(FTTokens.spaceMd),
        child: child,
      ),
    );
  }
}

class FTSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const FTSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: FTTokens.textPrimary,
                ),
              ),
              if ((subtitle ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      color: FTTokens.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class FTChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const FTChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: const Color(0xFFD9F3F7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? FTTokens.accent : FTTokens.textPrimary,
      ),
    );
  }
}

class FTPill extends StatelessWidget {
  final String text;
  final Color? bgColor;
  final Color? textColor;

  const FTPill({
    super.key,
    required this.text,
    this.bgColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor ?? const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? const Color(0xFF334155),
        ),
      ),
    );
  }
}

class FTSkeleton extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadiusGeometry? borderRadius;

  const FTSkeleton({
    super.key,
    this.height = 16,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

class FTEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FTEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: const Color(0xFF64748B)),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(color: FTTokens.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              FTPrimaryButton(label: actionLabel!, onPressed: onAction!),
            ],
          ],
        ),
      ),
    );
  }
}

class FTErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const FTErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FTEmptyState(
      icon: Icons.error_outline,
      title: 'Something went wrong',
      subtitle: message,
      actionLabel: onRetry == null ? null : 'Retry',
      onAction: onRetry,
    );
  }
}

class FTPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  const FTPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.chevron_right),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: FTTokens.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FTTokens.radiusSm),
        ),
      ),
    );
  }
}

class FTSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const FTSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon ?? Icons.chevron_right),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: FTTokens.textPrimary,
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FTTokens.radiusSm),
        ),
      ),
    );
  }
}
