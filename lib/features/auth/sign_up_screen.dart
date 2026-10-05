import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_ui.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';
import 'auth_form_parts.dart';
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
  void initState() {
    super.initState();
    widget.authRepository.activeCompanyContext.addListener(
      _onAuthenticatedAfterConfirmation,
    );
  }

  @override
  void dispose() {
    widget.authRepository.activeCompanyContext.removeListener(
      _onAuthenticatedAfterConfirmation,
    );
    _emailController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onAuthenticatedAfterConfirmation() {
    if (!_awaitingConfirmation || !mounted) return;
    final user = widget.authRepository.currentUser;
    if (user == null) return;
    setState(() => _awaitingConfirmation = false);
    Navigator.of(context).pushReplacementNamed(
      user.role == UserRole.admin
          ? AppRoutes.adminDashboard
          : AppRoutes.secretaryDashboard,
    );
  }

  Future<void> _submit() async {
    // Guard before validation and before the first await. A rapid double tap or
    // an Enter key event must not create two independent Supabase requests.
    if (_working || _awaitingConfirmation) return;
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
          _formError =
              'Your account was created, but no company is available '
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
        () => _formError =
            'We could not create your account. '
            'Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // No AppBar here on purpose. The brand panel is already a full-height
    // layout, so an AppBar above it produced two stacked headers and pushed
    // the form below the fold. The form carries its own heading and the
    // brand panel carries the identity.
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: AppAuthBrandPanel(
          supportingText:
              'Create a company workspace, then invite your secretaries.',
          child: _awaitingConfirmation
              ? _buildConfirmationNotice()
              : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildConfirmationNotice() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppAuthHeader(
          title: 'Check your email',
          subtitle:
              'Open the confirmation link we sent to finish activating your '
              'account, then sign in.',
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
            children: [
              Icon(Icons.mail_outline, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _emailController.text.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppAuthHeader(
            title: 'Create your account',
            subtitle:
                'Registering a company name makes you its owner. Leave it blank '
                'to join a company that already exists.',
          ),
          const SizedBox(height: 26),
          AuthLabeledField(
            label: 'Company name',
            child: TextFormField(
              controller: _companyController,
              enabled: !_working,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'Optional for existing companies',
                errorText: _companyError,
              ),
              validator: (value) => (value?.trim().length ?? 0) > 120
                  ? 'That company name is too long.'
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          AuthLabeledField(
            label: 'Your name',
            child: TextFormField(
              controller: _nameController,
              enabled: !_working,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Full name'),
              validator: (value) => (value?.trim().length ?? 0) > 120
                  ? 'That name is too long.'
                  : null,
            ),
          ),
          const SizedBox(height: 18),
          AuthLabeledField(
            label: 'Email address',
            child: TextFormField(
              controller: _emailController,
              enabled: !_working,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
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
            ),
          ),
          const SizedBox(height: 18),
          AuthLabeledField(
            label: 'Password',
            child: AppPasswordField(
              controller: _passwordController,
              helperText: PasswordPolicy.requirementText,
              errorText: _passwordError,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !_working,
            ),
          ),
          const SizedBox(height: 18),
          AuthLabeledField(
            label: 'Confirm password',
            child: AppPasswordField(
              controller: _confirmController,
              errorText: _confirmError,
              autofillHints: const [AutofillHints.newPassword],
              enabled: !_working,
              onSubmitted: (_) => _submit(),
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
                  : const Text('Create account'),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: _working ? null : () => Navigator.of(context).pop(),
            style: authLinkStyle(context),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}
