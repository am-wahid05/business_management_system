import 'package:flutter/material.dart';

import 'account_service.dart';
import 'password_policy.dart';
import 'password_widgets.dart';

/// Sets a new password from a recovery link.
///
/// This screen is reached only from a genuine Supabase password-recovery event,
/// never from a normal sign-in. That distinction is the point of the screen: a
/// recovery session must not be able to fall through to a dashboard, because
/// doing so would skip the reset entirely and leave the user believing their
/// password had changed when it had not.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    required this.accountService,
    this.onCompleted,
    super.key,
  });

  final AccountService accountService;

  /// Called after a successful reset, so the recovery gate can step aside and
  /// hand control back to the normal sign-in flow.
  ///
  /// When null the screen falls back to clearing the navigator to the login
  /// route, which is what happens if the screen is reached directly.
  final VoidCallback? onCompleted;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _newError;
  String? _confirmError;
  String? _formError;
  bool _working = false;
  bool _done = false;

  @override
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _newController.text;
    setState(() {
      _newError = PasswordPolicy.validate(next);
      _confirmError = _newError == null
          ? PasswordPolicy.validateMatch(next, _confirmController.text)
          : null;
      _formError = null;
    });
    if (_newError != null || _confirmError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _working = true);
    try {
      await widget.accountService.resetPassword(next);
      if (!mounted) return;
      setState(() => _done = true);
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _formError = 'We could not change your password. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Leaves the recovery flow and returns to the login screen.
  ///
  /// The recovery session is signed out either way, so a link that has already
  /// been used cannot be replayed to start the flow a second time.
  Future<void> _returnToLogin() async {
    try {
      await widget.accountService.cancelRecovery();
    } catch (_) {
      // Leaving the flow must always be possible, even if the sign-out call
      // fails. The navigation below is what actually gets the user to safety.
    }
    if (!mounted) return;
    final onCompleted = widget.onCompleted;
    if (onCompleted != null) {
      onCompleted();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return PasswordFormScaffold(
        title: 'Password Changed',
        heading: 'All done',
        subtitle: 'Your password has been changed successfully.',
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          const Text(
            'You can now sign in with your new password.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _returnToLogin,
            child: const Text('Back to Login'),
          ),
        ],
      );
    }

    return PasswordFormScaffold(
      title: 'Reset Password',
      heading: 'Choose a New Password',
      subtitle: 'Set a new password for your account.',
      children: [
        AppPasswordField(
          controller: _newController,
          label: 'New password',
          helperText: PasswordPolicy.requirementText,
          errorText: _newError,
          autofillHints: const [AutofillHints.newPassword],
          enabled: !_working,
        ),
        const SizedBox(height: 16),
        AppPasswordField(
          controller: _confirmController,
          label: 'Confirm new password',
          errorText: _confirmError,
          autofillHints: const [AutofillHints.newPassword],
          enabled: !_working,
          onSubmitted: (_) => _submit(),
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
              : const Icon(Icons.lock_reset_outlined),
          label: const Text('Change Password'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _working ? null : _returnToLogin,
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
