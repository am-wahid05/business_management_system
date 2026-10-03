import '../auth/auth_models.dart';

/// The spreadsheet is an admin/owner management tool.
///
/// This uses the application's existing role and permission model. No new role
/// is introduced and no existing permission is changed: an admin already holds
/// [AppPermission.administerDatabase], which the secretary role explicitly does
/// not. The role check is kept alongside it so the rule stays readable and
/// fails closed if the permission model is ever widened.
const AppPermission spreadsheetPermission = AppPermission.administerDatabase;

/// Whether [user] may open and use the built-in spreadsheet.
///
/// A signed-out user, or a secretary, is not allowed. This is the single rule
/// used by the route, the screen and every action inside the screen.
bool canUseSpreadsheet(AppUser? user) {
  if (user == null) return false;
  if (user.role != UserRole.admin) return false;
  return user.can(spreadsheetPermission);
}
