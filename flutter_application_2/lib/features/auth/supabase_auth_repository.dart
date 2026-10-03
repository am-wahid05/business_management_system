import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'active_company_context.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this.client, {
    ActiveCompanyContext? activeCompanyContext,
    this.readSelectedCompanyId,
    this.writeSelectedCompanyId,
  }) : _activeCompanyContext = activeCompanyContext ?? ActiveCompanyContext() {
    _authStateSubscription = client.auth.onAuthStateChange.listen(
      _onAuthStateChange,
    );
  }

  final SupabaseClient client;
  final ActiveCompanyContext _activeCompanyContext;
  final Future<String?> Function()? readSelectedCompanyId;
  final Future<void> Function(String companyId)? writeSelectedCompanyId;
  late final StreamSubscription<AuthState> _authStateSubscription;
  List<CompanyMembership> _memberships = const [];

  Future<void> dispose() => _authStateSubscription.cancel();

  @override
  ActiveCompanyContext get activeCompanyContext => _activeCompanyContext;

  @override
  bool get isRemote => true;

  @override
  AppUser? get currentUser => _activeCompanyContext.value;

  @override
  Future<void> restoreSession() async {
    final session = client.auth.currentSession;
    if (session == null) {
      _memberships = const [];
      _activeCompanyContext.value = null;
      return;
    }
    await _loadAuthenticatedUser(session.user);
  }

  void _onAuthStateChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedOut || state.session == null) {
      _memberships = const [];
      _activeCompanyContext.value = null;
      return;
    }
    if (state.event == AuthChangeEvent.tokenRefreshed &&
        currentUser?.id == state.session!.user.id)
      return;
    final sessionUser = state.session!.user;
    if (currentUser?.id != sessionUser.id) {
      _memberships = const [];
      _activeCompanyContext.value = null;
    }
    unawaited(
      _loadAuthenticatedUser(sessionUser).catchError((Object _) {
        _memberships = const [];
        _activeCompanyContext.value = null;
        return null;
      }),
    );
  }

  Future<AppUser?> _loadAuthenticatedUser(User sessionUser) async {
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    final rows = await client
        .from('company_memberships')
        .select('company_id, role, is_active, companies(name, logo_path)')
        .eq('user_id', sessionUser.id)
        .eq('is_active', true);
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    if (rows.isEmpty) {
      _memberships = const [];
      _activeCompanyContext.value = null;
      return null;
    }
    final profile = await client
        .from('profiles')
        .select('display_name, is_active')
        .eq('id', sessionUser.id)
        .single();
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    if (profile['is_active'] != true) {
      _memberships = const [];
      _activeCompanyContext.value = null;
      return null;
    }
    _memberships = (rows as List)
        .map(_membershipFromRow)
        .toList(growable: false);
    final preferredCompanyId = await readSelectedCompanyId?.call();
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    final selected = _memberships.firstWhere(
      (membership) => membership.companyId == preferredCompanyId,
      orElse: () => _memberships.first,
    );
    _activeCompanyContext.value = AppUser(
      id: sessionUser.id,
      username: sessionUser.email ?? '',
      displayName: profile['display_name'] as String,
      role: selected.role,
      isActive: true,
      companyId: selected.companyId,
      companyName: selected.companyName,
      companyLogoPath: selected.logoPath,
    );
    await writeSelectedCompanyId?.call(selected.companyId);
    return _activeCompanyContext.value;
  }

  @override
  Future<bool> hasUsers() async {
    // Remote accounts can always sign in or start the explicit company signup flow.
    return true;
  }

  @override
  Future<AppUser?> signIn(String identifier, String password) async {
    try {
      final response = await client.auth.signInWithPassword(
        email: identifier.trim(),
        password: password,
      );
      final sessionUser = response.user;
      if (sessionUser == null) return null;
      final user = await _loadAuthenticatedUser(sessionUser);
      if (user == null) await signOut();
      return user;
    } on AuthException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<List<CompanyMembership>> companiesForCurrentUser() async =>
      _memberships;

  @override
  Future<void> selectCompany(String companyId) async {
    CompanyMembership? selected;
    for (final membership in _memberships) {
      if (membership.companyId == companyId) {
        selected = membership;
        break;
      }
    }
    if (selected == null)
      throw StateError('You do not belong to that company.');
    final current = currentUser;
    if (current == null)
      throw StateError('Sign in before selecting a company.');
    await writeSelectedCompanyId?.call(selected.companyId);
    _activeCompanyContext.value = current.copyWith(
      role: selected.role,
      companyId: selected.companyId,
      companyName: selected.companyName,
      companyLogoPath: selected.logoPath,
      clearCompanyLogoPath: selected.logoPath == null,
    );
  }

  @override
  Future<AppUser> createUser({
    required String username,
    required String displayName,
    required UserRole role,
    required String password,
    String? companyName,
  }) async {
    if (companyName == null) {
      final companyId = currentUser?.companyId;
      if (companyId == null)
        throw StateError('Sign in to a company before inviting a user.');
      final response = await client.functions.invoke(
        'invite-company-member',
        body: {
          'company_id': companyId,
          'email': username.trim(),
          'display_name': displayName.trim(),
          'password': password,
          'role': role.name,
        },
      );
      if (response.status < 200 || response.status >= 300) {
        final error = response.data is Map
            ? (response.data as Map)['error']
            : null;
        throw StateError(error?.toString() ?? 'Could not invite user');
      }
      final data = response.data as Map<String, dynamic>;
      final row = data['user'] as Map<String, dynamic>;
      return AppUser(
        id: row['id'] as String,
        username: row['username'] as String,
        displayName: row['display_name'] as String,
        role: UserRole.values.byName(row['role'] as String),
        isActive: row['is_active'] == true,
        companyId: companyId,
        companyName: currentUser?.companyName,
        companyLogoPath: currentUser?.companyLogoPath,
      );
    }
    if (role != UserRole.admin || companyName.trim().isEmpty) {
      throw StateError('Create an owner account with a company name.');
    }
    try {
      final response = await client.auth.signUp(
        email: username.trim(),
        password: password,
        data: {
          'display_name': displayName.trim(),
          'company_name': companyName.trim(),
        },
      );
      final sessionUser = response.user;
      if (sessionUser == null) {
        throw StateError(
          'Registration could not be completed. Check the email address and try again.',
        );
      }
      if (response.session == null) {
        throw StateError(
          'Account and company created. Confirm your email, then sign in.',
        );
      }
      final user = await _loadAuthenticatedUser(sessionUser);
      if (user == null)
        throw StateError(
          'Account created but company setup did not complete. Contact your administrator.',
        );
      return user;
    } on AuthException catch (error) {
      throw StateError(error.message);
    }
  }

  @override
  Future<List<AppUser>> allUsers() async {
    final companyId = currentUser?.companyId;
    if (companyId == null) return const [];
    final rows = await client
        .from('company_memberships')
        .select('role, is_active, profiles(id, email, display_name, is_active)')
        .eq('company_id', companyId)
        .order('created_at');
    return (rows as List)
        .map((item) {
          final row = item['profiles'] as Map<String, dynamic>;
          final membershipRole = item['role'] as String;
          return AppUser(
            id: row['id'] as String,
            username: (row['email'] as String?) ?? '',
            displayName: row['display_name'] as String,
            role: membershipRole == 'secretary'
                ? UserRole.secretary
                : UserRole.admin,
            isActive: item['is_active'] == true && row['is_active'] == true,
            companyId: companyId,
            companyName: currentUser?.companyName,
            companyLogoPath: currentUser?.companyLogoPath,
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
    _activeCompanyContext.value = null;
    _memberships = const [];
  }

  static CompanyMembership _membershipFromRow(dynamic row) {
    final company = row['companies'] as Map<String, dynamic>;
    return CompanyMembership(
      companyId: row['company_id'] as String,
      companyName: company['name'] as String,
      role: row['role'] == 'secretary' ? UserRole.secretary : UserRole.admin,
      logoPath: company['logo_path'] as String?,
    );
  }
}
