import 'package:flutter/material.dart';

import '../foundation/app_tokens.dart';
import 'ft_badge.dart';

class FTTile extends StatefulWidget {
  const FTTile({
    super.key,
    this.title,
    this.subtitle,
    this.leading,
    this.leadingWidget,
    this.titleWidget,
    this.subtitleWidget,
    this.trailing,
    this.badgeText,
    this.onTap,
  });

  final Object? title;
  final Object? subtitle;
  final Object? leading;
  final Widget? leadingWidget;
  final Widget? titleWidget;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final String? badgeText;
  final VoidCallback? onTap;

  @override
  State<FTTile> createState() => _FTTileState();
}

class _FTTileState extends State<FTTile> {
  bool _highlighted = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget effectiveTitle = widget.titleWidget ??
        (widget.title is Widget
            ? widget.title as Widget
            : Text(
                (widget.title ?? '').toString(),
                style: Theme.of(context).textTheme.titleMedium,
              ));
    final bool hasSubtitle = widget.subtitleWidget != null ||
        ((widget.subtitle ?? '').toString().trim().isNotEmpty);
    final Widget effectiveSubtitle = widget.subtitleWidget ??
        (widget.subtitle is Widget
            ? widget.subtitle as Widget
            : Text(
                (widget.subtitle ?? '').toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ));

    return AnimatedContainer(
      duration: AppTokens.d150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        border: Border.all(
          color: _highlighted
              ? scheme.primary.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.r12),
        onHighlightChanged: (value) {
          if (!mounted) return;
          setState(() => _highlighted = value);
        },
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s12,
            vertical: AppTokens.s12,
          ),
          child: Row(
            children: [
              if (widget.leadingWidget != null || widget.leading != null) ...[
                widget.leadingWidget ??
                    (widget.leading is Widget
                        ? widget.leading as Widget
                        : Icon(
                            widget.leading as IconData,
                            color: scheme.onSurfaceVariant,
                          )),
                const SizedBox(width: AppTokens.s12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    effectiveTitle,
                    if (hasSubtitle)
                      Padding(
                        padding: const EdgeInsets.only(top: AppTokens.s4),
                        child: effectiveSubtitle,
                      ),
                  ],
                ),
              ),
              if (widget.badgeText != null &&
                  widget.badgeText!.trim().isNotEmpty) ...[
                FTBadge(text: widget.badgeText!),
                const SizedBox(width: AppTokens.s8),
              ],
              widget.trailing ??
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
