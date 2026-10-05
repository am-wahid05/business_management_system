import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import 'account_service.dart';
import 'auth_form_parts.dart';

/// The confirmation shown whether or not the address is registered.
///
/// The wording is fixed and says nothing about whether a match was found, so
/// this screen cannot be used to discover which email addresses have accounts.
const String passwordResetSentMessage =
    'If an account exists for this email, a password reset link has been sent.';

/// Requests a password reset link by email.
///
/// Available to every signed-out user, so an admin and a secretary use exactly
/// the same flow: there is no separate per-role reset system. The only role
/// input on the login screen is which dashboard to open, which is decided after
/// sign-in by the account's real membership role.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({required this.accountService, super.key});

  final AccountService accountService;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _emailError;
  String? _formError;
  bool _working = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _formError = null;
      _emailError = null;
    });
    try {
      await widget.accountService.sendPasswordResetEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _sent = true);
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _formError =
            'We could not send the reset link. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar: the brand panel is already a full-height layout, so one above
    // it stacked two headers and pushed the form down.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: AppAuthBrandPanel(
          supportingText: 'We will email you a link to choose a new password.',
          child: _sent ? _buildSent(context) : _buildForm(context),
        ),
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppAuthHeader(
          title: 'Check your email',
          subtitle: passwordResetSentMessage,
        ),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.mail_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Follow the link in that email to choose a new password. The '
                  'link can only be used once, and it may expire.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppAuthHeader(
            title: 'Forgot your password?',
            subtitle:
                'Enter the email address you use to sign in and we will send '
                'you a link to choose a new password.',
          ),
          const SizedBox(height: 26),
          AuthLabeledField(
            label: 'Email address',
            child: TextFormField(
              controller: _emailController,
              enabled: !_working,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'you@company.com',
                errorText: _emailError,
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter your email address.';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 18),
            AppAuthError(_formError!),
          ],
          const SizedBox(height: 26),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _working ? null : _submit,
              child: _working
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Text('Send Reset Link'),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            style: authLinkStyle(context),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }
}
