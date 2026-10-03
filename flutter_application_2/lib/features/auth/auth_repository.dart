import 'auth_models.dart';
import 'active_company_context.dart';

abstract interface class AuthRepository {
  ActiveCompanyContext get activeCompanyContext;
  AppUser? get currentUser => activeCompanyContext.value;
  bool get isRemote;
  Future<void> restoreSession();
  Future<bool> hasUsers();
  Future<AppUser?> signIn(String identifier, String password);
  Future<List<CompanyMembership>> companiesForCurrentUser();
  Future<void> selectCompany(String companyId);
  Future<AppUser> createUser({
    required String username,
    required String displayName,
    required UserRole role,
    required String password,
    String? companyName,
  });
  Future<List<AppUser>> allUsers();
  Future<void> signOut();
}
