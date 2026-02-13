import 'package:flutter/material.dart';

class FTInput extends StatelessWidget {
  const FTInput({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      errorText: errorText,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      suffixIcon: suffixIcon == null ? null : Icon(suffixIcon),
    );

    if (controller != null) {
      return TextField(
        controller: controller,
        decoration: decoration,
        keyboardType: keyboardType,
        obscureText: obscureText,
        enabled: enabled,
        maxLines: maxLines,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
      );
    }

    return TextFormField(
      initialValue: initialValue,
      decoration: decoration,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: maxLines,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      textInputAction: textInputAction,
    );
  }
}
