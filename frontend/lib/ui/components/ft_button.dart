import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/app_tokens.dart';

enum FTButtonVariant {
  primary,
  secondary,
  ghost,
  destructive,
}

class FTButton extends StatefulWidget {
  const FTButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = FTButtonVariant.primary,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final FTButtonVariant variant;
  final bool loading;
  final bool expand;

  @override
  State<FTButton> createState() => _FTButtonState();
}

class _FTButtonState extends State<FTButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final bool enabled = widget.onPressed != null && !widget.loading;
    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _foregroundColor(scheme),
            ),
          ),
          const SizedBox(width: AppTokens.s8),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: 18),
          const SizedBox(width: AppTokens.s8),
        ],
        Text(widget.label),
      ],
    );

    return SizedBox(
      height: 48,
      width: widget.expand ? double.infinity : null,
      child: Listener(
        onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onPointerCancel:
            enabled ? (_) => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          duration: AppTokens.d150,
          curve: Curves.easeOut,
          scale: _pressed && enabled ? 0.98 : 1,
          child: _buildButton(context, child, enabled),
        ),
      ),
    );
  }

  Color _foregroundColor(ColorScheme scheme) {
    switch (widget.variant) {
      case FTButtonVariant.primary:
        return scheme.onPrimary;
      case FTButtonVariant.secondary:
        return scheme.onSecondaryContainer;
      case FTButtonVariant.ghost:
        return scheme.primary;
      case FTButtonVariant.destructive:
        return scheme.onError;
    }
  }

  Color _backgroundColor(ColorScheme scheme) {
    switch (widget.variant) {
      case FTButtonVariant.primary:
        return scheme.primary;
      case FTButtonVariant.secondary:
        return scheme.secondaryContainer;
      case FTButtonVariant.ghost:
        return Colors.transparent;
      case FTButtonVariant.destructive:
        return scheme.error;
    }
  }

  Widget _buildButton(BuildContext context, Widget child, bool enabled) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTokens.r12),
      side: widget.variant == FTButtonVariant.ghost
          ? BorderSide(color: scheme.outlineVariant)
          : BorderSide.none,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: TextButton(
        onPressed: enabled
            ? () {
                if (widget.variant == FTButtonVariant.primary) {
                  HapticFeedback.selectionClick();
                }
                widget.onPressed?.call();
              }
            : null,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.surfaceContainerHighest;
            }
            return _backgroundColor(scheme);
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.disabled)) {
              return scheme.onSurfaceVariant;
            }
            return _foregroundColor(scheme);
          }),
        ),
        child: child,
      ),
    );
  }
}

class FTPrimaryButton extends StatelessWidget {
  const FTPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FTButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      loading: loading,
      expand: true,
      variant: FTButtonVariant.primary,
    );
  }
}

class FTSecondaryButton extends StatelessWidget {
  const FTSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return FTButton(
      label: label,
      onPressed: onPressed,
      icon: icon,
      loading: loading,
      expand: true,
      variant: FTButtonVariant.secondary,
    );
  }
}
