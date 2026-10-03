import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'account_service.dart';
import 'password_policy.dart';
import 'password_widgets.dart';

/// Creates the account, and optionally the company, for a new remote user.
///
/// There is deliberately no role selector on this screen. The server trigger
/// `handle_new_user()` gives the first registered user of a new company the
/// owner role, so the only thing this form collects that affects provisioning
/// is the company name. A user who enters one is creating a new company; a user
/// who leaves it blank registers an account that waits to be invited into an
/// existing company.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    required this.signUpService,
    required this.authRepository,
    super.key,
  });

  final SupabaseSignUpService signUpService;

  /// Used only to read the authenticated user back after a successful sign-up,
  /// so the new owner lands on the dashboard their membership actually grants.
  final AuthRepository authRepository;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  String? _emailError;
  String? _companyError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;
  bool _working = false;

  /// Set once the account exists but the address still needs confirming.
  bool _awaitingConfirmation = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }
  Future<void> _submit() async {
    final password = _passwordController.text;
    final company = _companyController.text.trim();
    setState(() {
      _emailError = null;
      _companyError = null;
      _passwordError = PasswordPolicy.validate(password);
      _confirmError = _passwordError == null
          ? PasswordPolicy.validateMatch(password, _confirmController.text)
          : null;
      _formError = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_passwordError != null || _confirmError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _working = true);
    try {
      final outcome = await widget.signUpService.register(
        email: _emailController.text.trim(),
        password: password,
        displayName: _nameController.text,
        companyName: company,
      );
      if (!mounted) return;
      if (outcome == SignUpOutcome.needsEmailConfirmation) {
        // No session yet, so there is nothing to open. Saying so plainly is
        // better than bouncing them to a login screen that would just fail.
        setState(() => _awaitingConfirmation = true);
        return;
      }
      // A session exists, but the profile, company and owner membership are
      // created by a database trigger inside the same signup transaction. Read
      // the user back through the normal repository path rather than assuming
      // anything, so a user with no usable company is never shown a dashboard.
      await widget.authRepository.restoreSession();
      final user = widget.authRepository.currentUser;
      if (!mounted) return;
      if (user == null) {
        setState(() {
          _formError = 'Your account was created, but no company is available '
              'for it yet. Please sign in again in a moment.';
        });
        return;
      }
      Navigator.of(context).pushReplacementNamed(
        user.role == UserRole.admin
            ? AppRoutes.adminDashboard
            : AppRoutes.secretaryDashboard,
      );
    } on SignUpException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _formError = 'We could not create your account. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _awaitingConfirmation
                  ? _buildConfirmationNotice()
                  : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmationNotice() {
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
          'Check your email',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a confirmation link to '
          '${_emailController.text.trim()}. Open it to activate your account, '
          'then sign in.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to Sign In'),
        ),
      ],
    );
  }
  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create your company account',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'The first person to register a company name becomes its owner. '
            'You can add secretaries afterwards.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _companyController,
            enabled: !_working,
            decoration: InputDecoration(
              labelText: 'Company name',
              helperText: 'Leave blank if you are joining an existing company.',
              errorText: _companyError,
            ),
            validator: (value) => (value?.trim().length ?? 0) > 120
                ? 'That company name is too long.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            enabled: !_working,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Your name'),
            validator: (value) => (value?.trim().length ?? 0) > 120
                ? 'That name is too long.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            enabled: !_working,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'Email address',
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
          ),
          const SizedBox(height: 16),
          AppPasswordField(
            controller: _passwordController,
            label: 'Password',
            helperText: PasswordPolicy.requirementText,
            errorText: _passwordError,
            autofillHints: const [AutofillHints.newPassword],
            enabled: !_working,
          ),
          const SizedBox(height: 16),
          AppPasswordField(
            controller: _confirmController,
            label: 'Confirm password',
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
                : const Icon(Icons.person_add_outlined),
            label: const Text('Create account'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            child: const Text('Back to Sign In'),
          ),
        ],
      ),
    );
  }
}