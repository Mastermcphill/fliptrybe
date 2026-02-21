import 'package:flutter/material.dart';

import '../foundation/tokens/ft_radius.dart';
import '../foundation/tokens/ft_spacing.dart';

InputDecoration _ftDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? helperText,
}) {
  final scheme = Theme.of(context).colorScheme;
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: FTSpacing.sm,
      vertical: FTSpacing.xs,
    ),
    border: OutlineInputBorder(
      borderRadius: FTRadius.roundedMd,
      borderSide: BorderSide(color: scheme.outlineVariant),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: FTRadius.roundedMd,
      borderSide: BorderSide(color: scheme.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: FTRadius.roundedMd,
      borderSide: BorderSide(color: scheme.primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: FTRadius.roundedMd,
      borderSide: BorderSide(color: scheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: FTRadius.roundedMd,
      borderSide: BorderSide(color: scheme.error, width: 1.4),
    ),
  );
}

class FTTextField extends StatelessWidget {
  const FTTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.prefixIcon,
    this.suffixIcon,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? minLines;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      autofillHints: autofillHints,
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
      decoration: _ftDecoration(
        context,
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

class FTPhoneField extends StatelessWidget {
  const FTPhoneField({
    super.key,
    this.controller,
    this.focusNode,
    this.nextFocusNode,
    this.labelText = 'Phone',
    this.hintText = '+234 801 234 5678',
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final FocusNode? nextFocusNode;
  final String labelText;
  final String hintText;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return FTTextField(
      controller: controller,
      focusNode: focusNode,
      nextFocusNode: nextFocusNode,
      labelText: labelText,
      hintText: hintText,
      errorText: errorText,
      keyboardType: TextInputType.phone,
      prefixIcon: Icons.phone_outlined,
      enabled: enabled,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      autofillHints: const [AutofillHints.telephoneNumber],
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
    this.helperText,
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
  final String? helperText;
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
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      enabled: widget.enabled,
      autofillHints: const [AutofillHints.password],
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
      decoration: _ftDecoration(
        context,
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: widget.enabled
              ? () => setState(() => _obscure = !_obscure)
              : null,
        ),
      ),
    );
  }
}

class FTDropDownField<T> extends StatelessWidget {
  const FTDropDownField({
    super.key,
    required this.items,
    this.initialValue,
    this.labelText,
    this.hintText,
    this.errorText,
    this.enabled = true,
    this.onChanged,
    this.isExpanded = true,
  });

  final List<DropdownMenuItem<T>> items;
  final T? initialValue;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final bool enabled;
  final bool isExpanded;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      items: items,
      isExpanded: isExpanded,
      onChanged: enabled ? onChanged : null,
      decoration: _ftDecoration(
        context,
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
      ),
    );
  }
}
