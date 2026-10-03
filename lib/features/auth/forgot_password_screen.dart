import 'package:flutter/material.dart';

import 'account_service.dart';
import 'password_widgets.dart';

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
        () => _formError = 'We could not send the reset link. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: _sent ? _buildSent(context) : _buildForm(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          passwordResetSentMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Follow the link in that email to choose a new password. The link can '
          'only be used once, and it may expire.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Login'),
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
          Text(
            'Forgot your password?',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the email address you use to sign in and we will send you a '
            'link to choose a new password.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _emailController,
            enabled: !_working,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'Email address',
              border: const OutlineInputBorder(),
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
          if (_formError != null) ...[
            const SizedBox(height: 16),
            PasswordErrorText(_formError!),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _working ? null : _submit,
            icon: _working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.send_outlined),
            label: const Text('Send Reset Link'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }
}
