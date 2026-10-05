import 'package:flutter/material.dart';

import '../../app/app_responsive.dart';
import 'account_service.dart';
import 'password_policy.dart';
import 'password_widgets.dart';

/// Lets a signed-in user change their own password.
///
/// Reachable by an admin, an owner and a secretary alike: changing your own
/// password is an account action, not a company management one, so it is not
/// gated by role or by the subscription. The real authorization is the
/// authenticated Supabase session plus the current password, which is verified
/// by the identity provider before anything is written.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({required this.accountService, super.key});

  final AccountService accountService;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _currentError;
  String? _newError;
  String? _confirmError;
  String? _formError;
  bool _working = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;
    setState(() {
      // The current password is only checked for presence here. Whether it is
      // actually correct is decided by Supabase, so the form never claims a
      // password is right or wrong on its own.
      _currentError = current.isEmpty ? 'Enter your current password.' : null;
      _newError = PasswordPolicy.validate(next);
      _confirmError = _newError == null
          ? PasswordPolicy.validateMatch(next, confirm)
          : null;
      _formError = null;
    });
    return _currentError == null && _newError == null && _confirmError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _working = true;
      _formError = null;
    });
    try {
      await widget.accountService.changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      // The session is deliberately kept. Supabase does not require a re-login
      // after a password change, so signing the user out here would be a
      // pointless extra step.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
      Navigator.of(context).pop();
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _formError =
            'We could not change your password. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.accountService;
    return PasswordFormScaffold(
      title: 'Change Password',
      // No heading override: the form's own heading is the screen title, so
      // "Change Password" stays on screen at every width instead of only
      // existing as an invisible property of this widget.
      subtitle: account.currentEmail == null
          ? 'Choose a new password for your account.'
          : 'Choose a new password for ${account.currentEmail}.',
      children: [
        AppPasswordField(
          controller: _currentController,
          label: 'Current password',
          errorText: _currentError,
          autofillHints: const [AutofillHints.password],
          enabled: !_working,
        ),
        const SizedBox(height: 16),
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
        // The button is full width on a phone and naturally sized on a desktop,
        // so it is always inside the visible area and always reachable.
        AppResponsive(
          maxWidth: double.infinity,
          centre: false,
          builder: (context, size) => FilledButton.icon(
            onPressed: _working ? null : _submit,
            icon: _working
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.lock_outline),
            // Deliberately not the same words as the screen title, so the page
            // never shows "Change Password" twice and the control is
            // unambiguous.
            label: const Text('Update password'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
