enum UserRole { admin, secretary }

enum AppPermission {
  receiveDeliveries,
  lookupSuppliers,
  viewTodaysRecords,
  correctDeliveries,
  viewSyncStatus,
  manageUsers,
  administerDatabase,
  configureSystem,
  unrestrictedDeletion,
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    required this.isActive,
    this.companyId,
    this.companyName,
    this.companyLogoPath,
  });

  final String id;
  final String username;
  final String displayName;
  final UserRole role;
  final bool isActive;
  final String? companyId;
  final String? companyName;
  final String? companyLogoPath;

  AppUser copyWith({
    String? username,
    String? displayName,
    UserRole? role,
    bool? isActive,
    String? companyId,
    String? companyName,
    String? companyLogoPath,
    bool clearCompanyLogoPath = false,
  }) => AppUser(
    id: id,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    isActive: isActive ?? this.isActive,
    companyId: companyId ?? this.companyId,
    companyName: companyName ?? this.companyName,
    companyLogoPath: clearCompanyLogoPath
        ? null
        : companyLogoPath ?? this.companyLogoPath,
  );

  bool can(AppPermission permission) {
    if (role == UserRole.admin) return true;
    return switch (permission) {
      AppPermission.receiveDeliveries ||
      AppPermission.lookupSuppliers ||
      AppPermission.viewTodaysRecords ||
      AppPermission.correctDeliveries ||
      AppPermission.viewSyncStatus => true,
      AppPermission.manageUsers ||
      AppPermission.administerDatabase ||
      AppPermission.configureSystem ||
      AppPermission.unrestrictedDeletion => false,
    };
  }
}

class CompanyMembership {
  const CompanyMembership({
    required this.companyId,
    required this.companyName,
    required this.role,
    this.logoPath,
  });

  final String companyId;
  final String companyName;
  final UserRole role;
  final String? logoPath;
}
