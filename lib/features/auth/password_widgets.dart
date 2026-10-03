import 'package:flutter/material.dart';

import '../../app/app_responsive.dart';
import 'account_service.dart';

/// A reusable password field with a show/hide control.
///
/// Used by every password screen so the reveal behaviour and the obscuring
/// toggle are identical everywhere, and so no screen can accidentally ship a
/// visible-by-default password field.
///
/// The value is never written anywhere: it lives only in this field's controller
/// and is handed straight to the [AccountService] on submit.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    required this.controller,
    required this.label,
    this.helperText,
    this.errorText,
    this.autofillHints,
    this.enabled = true,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? errorText;
  final List<String>? autofillHints;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscured = !_obscured),
          tooltip: _obscured ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// The shell shared by the Change Password and Reset Password screens.
///
/// Centred and width-capped, and scrollable, so the same screen is usable in a
/// 400px phone and on a 2560px monitor without the form stretching or the button
/// falling off the bottom behind the keyboard.
class PasswordFormScaffold extends StatelessWidget {
  const PasswordFormScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    this.heading,
    super.key,
  });

  /// The AppBar title, which also names the screen.
  final String title;

  /// The large heading in the body.
  ///
  /// Defaults to [title]. A screen passes a different value when the same words
  /// would otherwise appear twice on one page, which reads as a duplication bug
  /// and makes the label ambiguous.
  final String? heading;

  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: AppResponsive(
            maxWidth: AppBreakpoints.formMaxWidth,
            builder: (context, size) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  heading ?? title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows an error message in the app's error colour.
class PasswordErrorText extends StatelessWidget {
  const PasswordErrorText(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  );
}
