import 'package:flutter/material.dart';

/// A titled card holding one product's details on the billing screen.
class Section extends StatelessWidget {
  const Section({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A label and its value on one line.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {this.strong = false, super.key});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = strong
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Flexible(child: Text(value, style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// A renewal, lock or connectivity notice.
class Notice extends StatelessWidget {
  const Notice({required this.message, this.critical = false, super.key});

  final String message;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: critical ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message),
    );
  }
}

/// A pay action that explains the current state rather than faking a charge.
///
/// The note is always visible, so a user is never left wondering whether
/// pressing the button charged them.
class PayButton extends StatelessWidget {
  const PayButton({
    required this.label,
    required this.note,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String note;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton(onPressed: onPressed, child: Text(label)),
        const SizedBox(height: 6),
        Text(note, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
