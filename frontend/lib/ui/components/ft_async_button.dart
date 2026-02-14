import 'package:flutter/material.dart';

import 'ft_button.dart';

class FTAsyncButton extends StatefulWidget {
  const FTAsyncButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = FTButtonVariant.primary,
    this.icon,
    this.expand = true,
    this.enabled = true,
    this.externalLoading = false,
    this.onError,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final FTButtonVariant variant;
  final IconData? icon;
  final bool expand;
  final bool enabled;
  final bool externalLoading;
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<FTAsyncButton> createState() => _FTAsyncButtonState();
}

class _FTAsyncButtonState extends State<FTAsyncButton> {
  bool _running = false;

  Future<void> _handlePress() async {
    if (_running || widget.externalLoading) return;
    final action = widget.onPressed;
    if (action == null || !widget.enabled) return;

    setState(() => _running = true);
    try {
      await action();
    } catch (error, stackTrace) {
      widget.onError?.call(error, stackTrace);
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _running || widget.externalLoading;
    return FTButton(
      label: widget.label,
      variant: widget.variant,
      icon: widget.icon,
      expand: widget.expand,
      loading: loading,
      onPressed: (!widget.enabled || loading || widget.onPressed == null)
          ? null
          : _handlePress,
    );
  }
}
