export 'ft_app_bar.dart';
export 'ft_badge.dart';
export 'ft_button.dart';
export 'ft_card.dart';
export 'ft_empty_state.dart';
export 'ft_input.dart';
export 'ft_scaffold.dart';
export 'ft_skeleton.dart';
export 'ft_tile.dart';
export 'ft_toast.dart';

import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';
import '../foundation/app_typography.dart';
import 'ft_button.dart';
import 'ft_card.dart';
import 'ft_empty_state.dart';

class FTSectionHeader extends StatelessWidget {
  const FTSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.sectionTitle(context),
              ),
              if ((subtitle ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.s4),
                  child: Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.meta(context),
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppTokens.s8),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              alignment: Alignment.topRight,
              child: trailing!,
            ),
          ),
        ],
      ],
    );
  }
}

class FTResponsiveTitleAction extends StatelessWidget {
  const FTResponsiveTitleAction({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.breakpoint = 540,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.cardTitle(context),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: AppTokens.s4),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.meta(context),
          ),
        ],
      ],
    );

    if (action == null) {
      return textContent;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < breakpoint;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textContent,
              const SizedBox(height: AppTokens.s8),
              action!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: textContent),
            const SizedBox(width: AppTokens.s12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: action!,
            ),
          ],
        );
      },
    );
  }
}

class FTChip extends StatelessWidget {
  const FTChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
          ),
    );
  }
}

class FTSectionContainer extends StatelessWidget {
  const FTSectionContainer({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return FTCard(
      padding: padding ?? const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FTSectionHeader(title: title, subtitle: subtitle, trailing: trailing),
          const SizedBox(height: AppTokens.s12),
          child,
        ],
      ),
    );
  }
}

class FTMetricTile extends StatelessWidget {
  const FTMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FTCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppTypography.meta(context)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              if (icon != null)
                Icon(icon, size: 16, color: color ?? scheme.primary),
            ],
          ),
          const SizedBox(height: AppTokens.s8),
          Text(value, style: AppTypography.price(context)),
          if ((subtitle ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.s4),
              child: Text(subtitle!, style: AppTypography.meta(context)),
            ),
        ],
      ),
    );
  }
}

class FTLoadStateLayout extends StatelessWidget {
  const FTLoadStateLayout({
    super.key,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.empty,
    required this.emptyState,
    required this.loadingState,
    required this.child,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final bool empty;
  final Widget emptyState;
  final Widget loadingState;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget currentChild;
    final String stateKey;
    if (loading) {
      currentChild = loadingState;
      stateKey = 'loading';
    } else if (error != null) {
      currentChild = FTErrorState(message: error!, onRetry: onRetry);
      stateKey = 'error';
    } else if (empty) {
      currentChild = emptyState;
      stateKey = 'empty';
    } else {
      currentChild = child;
      stateKey = 'data';
    }
    return AnimatedSwitcher(
      duration: AppTokens.d200,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(key: ValueKey<String>(stateKey), child: currentChild),
    );
  }
}

class FTPrimaryCtaRow extends StatelessWidget {
  const FTPrimaryCtaRow({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FTPrimaryButton(label: primaryLabel, onPressed: onPrimary),
        ),
        if (secondaryLabel != null && onSecondary != null) ...[
          const SizedBox(width: AppTokens.s12),
          Expanded(
            child: FTSecondaryButton(
                label: secondaryLabel!, onPressed: onSecondary),
          ),
        ],
      ],
    );
  }
}
