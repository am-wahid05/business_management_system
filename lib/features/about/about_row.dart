import 'package:flutter/material.dart';

/// One labelled, optionally tappable row on the About page.
///
/// The row deliberately renders only a label and an affordance icon. It has no
/// field for showing a phone number or a URL as text, so neither the WhatsApp
/// number nor a website address can leak into the interface through this widget.
class AboutRow extends StatelessWidget {
  const AboutRow({
    required this.icon,
    required this.label,
    required this.isEnabled,
    this.onTap,
    super.key,
  });

  final IconData icon;

  /// The visible label, for example "Website" or "WhatsApp".
  final String label;

  /// Whether a destination exists yet.
  ///
  /// This only controls appearance and whether the row responds to a tap. It is
  /// not a data source: nothing is read from the company or from a contact list.
  final bool isEnabled;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isEnabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: color,
                      // A row with no destination yet still reads as a label,
                      // not as a broken link.
                      fontWeight: isEnabled ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                // The trailing affordance is an open icon, never the number or
                // the URL.
                Icon(
                  isEnabled ? Icons.open_in_new : Icons.chevron_right,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
