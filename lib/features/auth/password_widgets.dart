import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import 'account_service.dart';

/// A reusable password field with a show/hide control.
///
/// Used by every password screen so the reveal behaviour and the obscuring
/// toggle are identical everywhere, and so no screen can accidentally ship a
/// visible-by-default password field.
///
/// This is a [TextFormField], not a [TextField], so the password participates
/// in the surrounding [Form]'s validation exactly like every other field. The
/// login form itself only reports the identifier, so a missing password is
/// caught by the form rather than being sent to the server as an empty string.
///
/// The value is never written anywhere: it lives only in this field's controller
/// and is handed straight to the [AccountService] on submit.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.autofillHints,
    this.enabled = true,
    this.onSubmitted,
    this.validator,
    super.key,
  });

  /// The floating in-field label.
  ///
  /// Optional, because screens that place their own label above the field (as
  /// the sign-in and sign-up forms do) leave it null and pass a [hintText]
  /// instead.
  final String? label;

  /// Placeholder text shown inside the field when it is empty.
  final String? hintText;

  /// The field's text. Never written anywhere: it lives only in the caller's
  /// controller and is handed straight to the account service on submit.
  final TextEditingController controller;

  final String? helperText;
  final String? errorText;
  final List<String>? autofillHints;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  /// Optional in-form validator, so a screen can require a value without the
  /// field having to own that rule.
  final FormFieldValidator<String>? validator;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscured = !_obscured),
          tooltip: _obscured ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// The shell shared by the Change Password and Reset Password screens.
///
/// Centred, width-capped and scrollable, so the same screen is usable in a
/// 400px phone and on a 2560px monitor without the form stretching or the
/// button falling off the bottom behind the keyboard.
///
/// There is no AppBar here. The brand panel already provides a full-height
/// layout with its own identity, so an AppBar above it stacked two headers on
/// one screen and pushed the form down. A back control sits inside the form
/// instead, where it is unambiguous.
class PasswordFormScaffold extends StatelessWidget {
  const PasswordFormScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    this.heading,
    this.onBack,
    super.key,
  });

  /// Names the screen and is used as the brand-panel heading.
  final String title;

  /// The large heading in the body.
  ///
  /// Defaults to [title]. A screen passes a different value when the same words
  /// would otherwise appear twice on one page, which reads as a duplication bug
  /// and makes the label ambiguous.
  final String? heading;

  final String subtitle;
  final List<Widget> children;

  /// Overrides the default back behaviour, which pops this screen.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: AppAuthBrandPanel(
          companyName: null,
          // The subtitle belongs to the form's own header. Passing it to the
          // brand panel as well would print the same sentence twice on a wide
          // window, once in white on the panel and once above the form.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppAuthHeader(title: heading ?? title, subtitle: subtitle),
              const SizedBox(height: 26),
              ...children,
            ],
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
