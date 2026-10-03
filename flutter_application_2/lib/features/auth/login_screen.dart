import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import 'auth_models.dart';
import 'active_company_context.dart';
import 'auth_repository.dart';
import '../company/company_branding.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authRepository,
    required this.activeCompanyContext,
    this.brandingService,
    this.onAuthenticated,
    super.key,
  });

  final AuthRepository authRepository;
  final ActiveCompanyContext activeCompanyContext;
  final CompanyBrandingService? brandingService;
  final Future<void> Function(AppUser user)? onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasUsers = true;
  bool _loading = true;
  bool _creatingCompany = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _companyNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUserState() async {
    final hasUsers = await widget.authRepository.hasUsers();
    if (mounted)
      setState(() {
        _hasUsers = hasUsers;
        _loading = false;
      });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var user = _hasUsers
          ? (_creatingCompany
                ? await widget.authRepository.createUser(
                    username: _usernameController.text,
                    displayName: _displayNameController.text,
                    role: UserRole.admin,
                    password: _passwordController.text,
                    companyName: _companyNameController.text,
                  )
                : await widget.authRepository.signIn(
                    _usernameController.text,
                    _passwordController.text,
                  ))
          : await widget.authRepository.createUser(
              username: _usernameController.text,
              displayName: _displayNameController.text,
              role: UserRole.admin,
              password: _passwordController.text,
            );
      if (user == null) {
        setState(() => _error = 'Invalid username or password.');
        return;
      }
      if (_hasUsers && !_creatingCompany) {
        final memberships = await widget.authRepository
            .companiesForCurrentUser();
        if (!mounted) return;
        if (memberships.length > 1) {
          final selectedCompanyId = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Choose a company'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: memberships
                    .map(
                      (membership) => ListTile(
                        title: Text(membership.companyName),
                        subtitle: Text(membership.role.name),
                        onTap: () =>
                            Navigator.pop(context, membership.companyId),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
          if (selectedCompanyId == null) {
            await widget.authRepository.signOut();
            return;
          }
          await widget.authRepository.selectCompany(selectedCompanyId);
          user = widget.authRepository.currentUser!;
        }
      }
      await widget.onAuthenticated?.call(user);
      if (mounted)
        Navigator.pushReplacementNamed(
          context,
          user.role == UserRole.admin
              ? AppRoutes.adminDashboard
              : AppRoutes.secretaryDashboard,
        );
    } on ArgumentError catch (error) {
      setState(() => _error = error.message);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup =
        !_hasUsers || (widget.authRepository.isRemote && _creatingCompany);
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
                        Center(
                          child: CompanyBrandMark(
                            context: widget.activeCompanyContext,
                            service: widget.brandingService,
                            logoSize: 64,
                            nameStyle: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          setup
                              ? 'Create the first owner account'
                              : 'Sign in to continue',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
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
                          if (widget.authRepository.isRemote) ...[
                            TextFormField(
                              controller: _companyNameController,
                              decoration: const InputDecoration(
                                labelText: 'Company name',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Required'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                        TextFormField(
                          controller: _usernameController,
                          keyboardType: widget.authRepository.isRemote
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          autofillHints: [
                            widget.authRepository.isRemote
                                ? AutofillHints.email
                                : AutofillHints.username,
                          ],
                          decoration: InputDecoration(
                            labelText: widget.authRepository.isRemote
                                ? 'Email address'
                                : 'Username',
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (widget.authRepository.isRemote) {
                              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(text)
                                  ? null
                                  : 'Enter a valid email address';
                            }
                            return text.length >= 3
                                ? null
                                : 'Use at least 3 characters';
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (value) =>
                              value == null || value.length < 8
                              ? 'Use at least 8 characters'
                              : null,
                        ),
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
                        if (widget.authRepository.isRemote) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _loading
                                ? null
                                : () => setState(() {
                                    _creatingCompany = !_creatingCompany;
                                    _error = null;
                                  }),
                            child: Text(
                              _creatingCompany
                                  ? 'Already have an account? Sign in'
                                  : 'Create a new company account',
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          setup
                              ? 'Choose and remember your password. It will not be stored as plain text.'
                              : widget.authRepository.isRemote
                              ? 'Sign in with your Supabase account.'
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
}
