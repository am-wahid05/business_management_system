import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../company/company_branding.dart';
import 'active_company_context.dart';
import 'account_service.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'forgot_password_screen.dart';
import 'local_auth_repository.dart';
import 'sign_up_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authRepository,
    this.accountService,
    this.activeCompanyContext,
    this.brandingService,
    this.onAuthenticated,
    this.signUpService,
    super.key,
  });

  final AuthRepository authRepository;
  final AccountService? accountService;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;
  final Future<void> Function(AppUser user)? onAuthenticated;

  /// Null in the local-only setup, where accounts are seeded rather than
  /// registered. The remote registration link is hidden when it is absent,
  /// so the app never offers a sign-up that cannot work.
  final SupabaseSignUpService? signUpService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasUsers = true;
  bool _loading = true;
  UserRole _selectedRole = UserRole.admin;
  String? _error;

  bool get _remote => widget.authRepository.isRemote;

  @override
  void initState() {
    super.initState();
    _loadUserState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserState() async {
    final currentUser = widget.authRepository.currentUser;
    if (_remote && currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openDashboard(currentUser);
      });
      return;
    }
    final hasUsers = await widget.authRepository.hasUsers();
    if (mounted) {
      setState(() {
        _hasUsers = hasUsers;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _hasUsers || _remote
          ? await widget.authRepository.signIn(
              _usernameController.text,
              _passwordController.text,
            )
          : await widget.authRepository.createUser(
              username: _usernameController.text,
              displayName: _displayNameController.text,
              role: UserRole.admin,
              password: _passwordController.text,
            );
      if (user == null) {
        setState(() {
          _error = _remote
              ? 'Email or password is incorrect.'
              : 'Invalid username or password.';
        });
        return;
      }
      var authenticatedUser = user;
      if (_remote) {
        final memberships = await widget.authRepository
            .companiesForCurrentUser();
        if (memberships.length > 1) {
          if (!mounted) return;
          final companyId = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Choose a company'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: memberships
                    .map(
                      (membership) => ListTile(
                        title: Text(membership.companyName),
                        subtitle: Text(
                          membership.role == UserRole.admin
                              ? 'Admin'
                              : 'Secretary',
                        ),
                        onTap: () => Navigator.pop(
                          context,
                          membership.companyId,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          );
          if (companyId == null) {
            await widget.authRepository.signOut();
            return;
          }
          await widget.authRepository.selectCompany(companyId);
          authenticatedUser = widget.authRepository.currentUser ?? user;
        }

        // The tab is only a UI preference. The authoritative role is the one
        // company membership gives for the ACTIVE company, so this check runs
        // after any company selection, never before it. A mismatch signs the
        // user straight back out: leaving a valid session open behind a
        // rejected tab would leave the app one tap away from the dashboard the
        // tab was meant to be guarding.
        final roleError = roleMismatchMessage(
          selected: _selectedRole,
          actual: authenticatedUser.role,
        );
        if (roleError != null) {
          await widget.authRepository.signOut();
          if (!mounted) return;
          setState(() => _error = roleError);
          return;
        }
      } else {
        final roleError = roleMismatchMessage(
          selected: _selectedRole,
          actual: user.role,
        );
        if (roleError != null) {
          setState(() => _error = roleError);
          return;
        }
      }
      await widget.onAuthenticated?.call(authenticatedUser);
      if (mounted) _openDashboard(authenticatedUser);
    } on ArgumentError catch (error) {
      setState(() => _error = error.message);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() {
        _error = _remote
            ? 'Unable to sign in. Check your connection and try again.'
            : 'Unable to complete sign in. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDashboard(AppUser user) {
    Navigator.pushReplacementNamed(
      context,
      user.role == UserRole.admin
          ? AppRoutes.adminDashboard
          : AppRoutes.secretaryDashboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final setup = !_remote && !_hasUsers;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.activeCompanyContext
                            case final activeContext?)
                          Center(
                            child: CompanyBrandMark(
                              context: activeContext,
                              service: widget.brandingService,
                              logoSize: 64,
                              nameStyle: Theme.of(context).textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          )
                        else ...[
                          Icon(
                            Icons.business_outlined,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Business Management System',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          setup
                              ? 'Create the first owner account'
                              : 'Sign in to continue',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        // The tabs are shown for remote sign-in too. They are only a UI preference and
                        // are validated against company membership after
                        // authentication, so offering them here cannot grant a
                        // role.
                        if (!setup) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _roleButton(
                                  context,
                                  UserRole.admin,
                                  Icons.admin_panel_settings_outlined,
                                  'Login as Admin',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _roleButton(
                                  context,
                                  UserRole.secretary,
                                  Icons.badge_outlined,
                                  'Login as Secretary',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your dashboard is decided by your company role, '
                            'not by this choice.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (setup) ...[
                          TextFormField(
                            controller: _displayNameController,
                            decoration: const InputDecoration(
                              labelText: 'Owner name',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _usernameController,
                          keyboardType: _remote
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          autofillHints: [
                            _remote
                                ? AutofillHints.email
                                : AutofillHints.username,
                          ],
                          decoration: InputDecoration(
                            labelText: _remote ? 'Email address' : 'Username',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? (_remote
                                    ? 'Enter your email address'
                                    : 'Required')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                          onFieldSubmitted: (_) => _loading ? null : _submit(),
                        ),
                        if (!_remote && !setup) ...[
                          const SizedBox(height: 12),
                          Text(
                            'LOCAL TEST ADMIN: ${LocalAuthRepository.testUsername} / ${LocalAuthRepository.testPassword}\nLOCAL TEST SECRETARY: ${LocalAuthRepository.testSecretaryUsername} / ${LocalAuthRepository.testSecretaryPassword}',
                            textAlign: TextAlign.center,
                          ),
                        ],
                        if (_remote && widget.signUpService != null) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => SignUpScreen(
                                          signUpService: widget.signUpService!,
                                          authRepository: widget.authRepository,
                                        ),
                                      ),
                                    ),
                              child: const Text('Create a company account'),
                            ),
                          ),
                        ],
                        if (_remote && widget.accountService != null) ...[
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ForgotPasswordScreen(
                                          accountService:
                                              widget.accountService!,
                                        ),
                                      ),
                                    ),
                              child: const Text('Forgot password?'),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(),
                                  )
                                : Icon(
                                    setup
                                        ? Icons.person_add_alt_1
                                        : Icons.login,
                                  ),
                            label: Text(
                              setup ? 'Create Owner Account' : 'Sign In',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          setup
                              ? 'Choose and remember your password. It will not be stored as plain text.'
                              : _remote
                              ? 'Credentials are checked securely by Supabase Auth.'
                              : 'Passwords are checked locally and never displayed.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleButton(
    BuildContext context,
    UserRole role,
    IconData icon,
    String label,
  ) {
    final selected = _selectedRole == role;
    return selected
        ? FilledButton.icon(
            onPressed: () {},
            icon: Icon(icon),
            label: Text(label, textAlign: TextAlign.center),
          )
        : OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _selectedRole = role;
                _error = null;
                // Pre-filling the local demo accounts is a convenience for the
                // offline setup only. On a remote sign-in the identifier must
                // be the user's real email, so it is left untouched.
                if (!_remote) {
                  _usernameController.text = role == UserRole.admin
                      ? LocalAuthRepository.testUsername
                      : LocalAuthRepository.testSecretaryUsername;
                  _passwordController.clear();
                }
              });
            },
            icon: Icon(icon),
            label: Text(label, textAlign: TextAlign.center),
          );
  }
}

/// Checks a locally selected role tab against the account's real role.
///
/// This is a confirmation, never a grant. The tab carries no authority: the
/// [actual] role always comes from the authenticated user's company membership
/// on the server, and this function only decides whether the two agree. A null
/// result means the user may continue.
///
/// The wording deliberately names only the role the user already chose and the
/// role their own account has. It reveals nothing about other accounts, other
/// companies or who works there.
String? roleMismatchMessage({
  required UserRole selected,
  required UserRole actual,
}) {
  if (selected == actual) return null;
  final requested = selected == UserRole.admin ? 'Admin' : 'Secretary';
  final permitted = actual == UserRole.admin ? 'Admin' : 'Secretary';
  final article = actual == UserRole.admin ? 'an' : 'a';
  return 'You are not authorized to log in as $requested. This account is '
      'registered as $article $permitted. Sign in as $permitted.';
}
