import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/kolo_tokens.dart';

/// Champ de saisie standard, avec libellé au-dessus (plus lisible qu'un
/// libellé flottant à 130 % de taille de texte).
class KoloTextField extends StatelessWidget {
  const KoloTextField({
    required this.label,
    super.key,
    this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.enabled = true,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool autofocus;
  final int? maxLength;
  final int? maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: KoloSpacing.sm),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          autofocus: autofocus,
          maxLength: maxLength,
          maxLines: maxLines,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          autofillHints: autofillHints,
          textCapitalization: textCapitalization,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: hint,
            errorText: errorText,
            helperText: helperText,
            suffixIcon: suffix,
            errorMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
