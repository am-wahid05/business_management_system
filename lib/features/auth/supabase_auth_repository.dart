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

  Future<void> dispose() => _authStateSubscription.cancel();

  @override
  ActiveCompanyContext get activeCompanyContext => _activeCompanyContext;

  @override
  bool get isRemote => true;

  @override
  AppUser? get currentUser => _activeCompanyContext.value;

  @override
  Future<void> restoreSession() async {
    final user = client.auth.currentUser;
    if (user == null) {
      _activeCompanyContext.value = null;
      return;
    }
    await _loadAuthenticatedUser(user);
  }

  void _onAuthStateChange(AuthState state) {
    final session = state.session;
    if (state.event == AuthChangeEvent.signedOut || session == null) {
      _activeCompanyContext.value = null;
      return;
    }
    if (state.event == AuthChangeEvent.tokenRefreshed &&
        currentUser?.id == session.user.id) {
      return;
    }
    if (currentUser?.id != session.user.id) {
      _activeCompanyContext.value = null;
    }
    unawaited(
      _loadAuthenticatedUser(session.user).catchError((Object _) {
        _activeCompanyContext.value = null;
        return null;
      }),
    );
  }

  @override
  Future<bool> hasUsers() async => true;

  @override
  Future<AppUser?> signIn(String identifier, String password) async {
    try {
      final response = await client.auth.signInWithPassword(email: identifier.trim(), password: password);
      final sessionUser = response.user;
      if (sessionUser == null) return null;
      final user = await _loadAuthenticatedUser(sessionUser);
      if (user == null) await signOut();
      return user;
    } on AuthException catch (error) {
      throw StateError(error.message);
    }
  }

  Future<AppUser?> _loadAuthenticatedUser(User sessionUser) async {
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    final profile = await client
        .from('profiles')
        .select('display_name, is_active')
        .eq('id', sessionUser.id)
        .maybeSingle();
    if (client.auth.currentUser?.id != sessionUser.id ||
        profile == null ||
        profile['is_active'] != true) {
      _activeCompanyContext.value = null;
      return null;
    }

    final memberships = await _loadMemberships(sessionUser.id);
    if (memberships.isEmpty || client.auth.currentUser?.id != sessionUser.id) {
      _activeCompanyContext.value = null;
      return null;
    }
    final preferredId = await readSelectedCompanyId?.call();
    if (client.auth.currentUser?.id != sessionUser.id) return null;
    final selected = memberships.firstWhere(
      (membership) => membership.companyId == preferredId,
      orElse: () => memberships.first,
    );
    final user = AppUser(
      id: sessionUser.id,
      username: sessionUser.email ?? '',
      displayName: profile['display_name'] as String,
      role: selected.role,
      isActive: true,
      companyId: selected.companyId,
      companyName: selected.companyName,
      companyLogoPath: selected.logoPath,
      companySmsSenderId: selected.smsSenderId,
    );
    _activeCompanyContext.value = user;
    await writeSelectedCompanyId?.call(selected.companyId);
    return user;
  }

  Future<List<CompanyMembership>> _loadMemberships(String userId) async {
    final rows = await client
        .from('company_memberships')
        .select(
          'company_id, role, is_active, companies(name, logo_path, sms_sender_id)',
        )
        .eq('user_id', userId)
        .eq('is_active', true)
        .order('created_at');
    return (rows as List).map(_membershipFromRow).toList(growable: false);
  }

  @override
  Future<List<CompanyMembership>> companiesForCurrentUser() async {
    final userId = client.auth.currentUser?.id;
    if (userId == null) return const [];
    return _loadMemberships(userId);
  }

  @override
  Future<void> selectCompany(String companyId) async {
    final current = currentUser;
    if (current == null) throw StateError('Sign in before selecting a company.');
    final memberships = await companiesForCurrentUser();
    final selected = memberships.where((item) => item.companyId == companyId);
    if (selected.isEmpty) throw StateError('You do not belong to that company.');
    final membership = selected.first;
    final updated = current.copyWith(
      role: membership.role,
      companyId: membership.companyId,
      companyName: membership.companyName,
      companyLogoPath: membership.logoPath,
      clearCompanyLogoPath: membership.logoPath == null,
      companySmsSenderId: membership.smsSenderId,
      clearCompanySmsSenderId: membership.smsSenderId == null,
    );
    await writeSelectedCompanyId?.call(membership.companyId);
    _activeCompanyContext.value = updated;
  }

  @override
  Future<AppUser> createUser({required String username, required String displayName, required UserRole role, required String password}) async {
    throw StateError('Create Supabase users from the secured admin provisioning flow, not directly from the client.');
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
    return (rows as List).map((item) {
      final row = item['profiles'] as Map<String, dynamic>;
      final role = item['role'] as String;
      return AppUser(
        id: row['id'] as String,
        username: row['email'] as String? ?? '',
        displayName: row['display_name'] as String,
        role: role == 'secretary' ? UserRole.secretary : UserRole.admin,
        isActive: item['is_active'] == true && row['is_active'] == true,
        companyId: companyId,
        companyName: currentUser?.companyName,
        companyLogoPath: currentUser?.companyLogoPath,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> signOut() async {
    await client.auth.signOut();
    _activeCompanyContext.value = null;
  }

  static CompanyMembership _membershipFromRow(dynamic raw) {
    final row = Map<String, dynamic>.from(raw as Map);
    final company = Map<String, dynamic>.from(row['companies'] as Map);
    final role = row['role'] as String;
    return CompanyMembership(
      companyId: row['company_id'] as String,
      companyName: company['name'] as String,
      role: role == 'secretary' ? UserRole.secretary : UserRole.admin,
      logoPath: company['logo_path'] as String?,
      smsSenderId: company['sms_sender_id'] as String?,
    );
  }
}
