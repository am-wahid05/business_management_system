import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_ui.dart';
import '../company/company_branding.dart';
import 'active_company_context.dart';
import 'account_service.dart';
import 'auth_form_parts.dart';
import 'auth_models.dart';
import 'auth_repository.dart';
import 'forgot_password_screen.dart';
import 'local_auth_repository.dart';
import 'password_widgets.dart';
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

  /// Whether the user has actually touched the role selector.
  ///
  /// This is what keeps the earlier remote sign-in bug from returning. The tab
  /// carries no authority, so an untouched tab must not be treated as a choice:
  /// when [_roleChosen] is false the selected role is only the initial value the
  /// control happens to display, and checking it against the real role would
  /// reject every Secretary who never pressed the Secretary segment. Only once
  /// the user has genuinely selected a role does the tab mean anything, and only
  /// then is it worth confirming it against company membership.
  bool _roleChosen = false;

  String? _error;

  /// True while the "choose a company" dialog is open.
  ///
  /// The submit spinner is suppressed in this state. A dialog is modal, so the
  /// form behind it cannot be interacted with, and an endlessly animating
  /// spinner behind a modal is both misleading and something that never lets
  /// the UI settle.
  bool _choosingCompany = false;

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
          _choosingCompany = true;
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
                        onTap: () =>
                            Navigator.pop(context, membership.companyId),
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

        // The role tab is only a UI preference. The authoritative role is the
        // one company membership gives for the ACTIVE company, so this check
        // runs after any company selection, never before it.
        //
        // It only runs when the user actually chose a role. An untouched tab is
        // not a claim about the user, so it must never reject a legitimate
        // sign-in: that was the bug where a remote Secretary was turned away
        // purely because the control started out displaying Admin. A mismatch
        // signs the user straight back out, because leaving a valid session open
        // behind a rejected choice would leave the app one tap away from the
        // dashboard the choice was meant to be guarding.
        if (_roleChosen) {
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
        }
      } else if (_roleChosen) {
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
      _choosingCompany = false;
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

    // Before the account check finishes there is nothing to say about the form
    // itself, so a skeleton holds the layout rather than a spinner over a blank
    // panel.
    if (_loading && !_hasUsers) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: AppAuthBrandPanel(
            companyName: widget.activeCompanyContext?.companyName,
            child: const AuthFormSkeleton(),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: AppAuthBrandPanel(
          companyName: widget.activeCompanyContext?.companyName,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppAuthHeader(
                  title: setup ? 'Create your owner account' : 'Sign in',
                  subtitle: setup
                      ? 'This installation has no accounts yet. Create the '
                            'first owner account to get started.'
                      : 'Use the email address and password for your company '
                            'account.',
                ),
                const SizedBox(height: 28),
                // The role choice is offered on a remote sign-in as well as a local
                // one.
                //
                // It is only a UI preference and never a grant: the
                // authoritative role always comes from the authenticated
                // user's company membership on the server, and the tab is
                // checked against it after authentication. Showing it on a
                // remote sign-in is therefore safe, and it lets a user see up
                // front which kind of account they are signing in to.
                if (!setup) ...[
                  AuthRoleSelector(
                    selected: _selectedRole,
                    enabled: !_loading,
                    onSelected: _selectRole,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your dashboard is decided by your company role, not by '
                    'this choice.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                AuthLabeledField(
                  label: _remote ? 'Email address' : 'Username',
                  child: TextFormField(
                    controller: _usernameController,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: _remote
                          ? 'you@company.com'
                          : 'Enter your username',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? (_remote ? 'Enter your email address' : 'Required')
                        : null,
                  ),
                ),
                const SizedBox(height: 18),
                AuthLabeledField(
                  label: 'Password',
                  child: AppPasswordField(
                    controller: _passwordController,
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.password],
                    // The password is required too. Without this the form would
                    // send an empty password to the server instead of
                    // explaining the problem here.
                    validator: (value) =>
                        (value?.isEmpty ?? true) ? 'Required' : null,
                    onSubmitted: (_) => _loading ? null : _submit(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  AppAuthError(_error!),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading && !_choosingCompany
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(setup ? 'Create owner account' : 'Sign In'),
                  ),
                ),
                const SizedBox(height: 16),
                AuthLinks(
                  showSignUp: _remote && widget.signUpService != null,
                  showForgotPassword: _remote && widget.accountService != null,
                  onSignUp: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SignUpScreen(
                        signUpService: widget.signUpService!,
                        authRepository: widget.authRepository,
                      ),
                    ),
                  ),
                  onForgotPassword: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ForgotPasswordScreen(
                        accountService: widget.accountService!,
                      ),
                    ),
                  ),
                ),
                if (!_remote && !setup) ...[
                  const SizedBox(height: 22),
                  const LocalAccountsHint(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectRole(UserRole role) {
    setState(() {
      _selectedRole = role;
      // Record that this is now a real choice rather than the control's initial
      // display value, so the role gate knows it may act on it.
      _roleChosen = true;
      _error = null;
      // Pre-filling the local demo accounts is a convenience for the offline
      // setup only. On a remote sign-in the identifier must be the user's real
      // email, so it is left untouched.
      if (!_remote) {
        _usernameController.text = role == UserRole.admin
            ? LocalAuthRepository.testUsername
            : LocalAuthRepository.testSecretaryUsername;
        _passwordController.clear();
      }
    });
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
