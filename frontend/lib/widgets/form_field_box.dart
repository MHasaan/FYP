import 'package:flutter/material.dart';

/// Wraps a form input with a label-above-input layout and consistent spacing.
class FormFieldBox extends StatelessWidget {
  final String label;
  final String? helper;
  final Widget child;
  final bool required;

  const FormFieldBox({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            text: label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
            children: required
                ? [
                    TextSpan(
                      text: '  *',
                      style: TextStyle(color: cs.error),
                    ),
                  ]
                : [],
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
