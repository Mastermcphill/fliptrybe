import 'package:flutter/material.dart';

import '../design/ft_tokens.dart';

class FTTextField extends StatelessWidget {
  const FTTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.labelText,
    this.hintText,
    this.errorText,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? minLines;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      textInputAction: textInputAction ??
          (nextFocusNode == null ? TextInputAction.done : TextInputAction.next),
      onSubmitted: (value) {
        if (nextFocusNode != null) {
          FocusScope.of(context).requestFocus(nextFocusNode);
        } else {
          FocusScope.of(context).unfocus();
        }
        onSubmitted?.call(value);
      },
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FTDesignTokens.md,
          vertical: FTDesignTokens.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}

class FTPasswordField extends StatefulWidget {
  const FTPasswordField({
    super.key,
    this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.labelText = 'Password',
    this.hintText,
    this.errorText,
    this.textInputAction,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final String labelText;
  final String? hintText;
  final String? errorText;
  final TextInputAction? textInputAction;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<FTPasswordField> createState() => _FTPasswordFieldState();
}

class _FTPasswordFieldState extends State<FTPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction ??
          (widget.nextFocusNode == null
              ? TextInputAction.done
              : TextInputAction.next),
      onSubmitted: (value) {
        if (widget.nextFocusNode != null) {
          FocusScope.of(context).requestFocus(widget.nextFocusNode);
        } else {
          FocusScope.of(context).unfocus();
        }
        widget.onSubmitted?.call(value);
      },
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: widget.enabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: FTDesignTokens.md,
          vertical: FTDesignTokens.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: FTDesignTokens.roundedMd,
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }
}
