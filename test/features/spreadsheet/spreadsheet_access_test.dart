import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/spreadsheet/spreadsheet_access.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _user(UserRole role, {bool isActive = true}) => AppUser(
  id: 'u-${role.name}',
  username: role.name,
  displayName: role.name,
  role: role,
  isActive: isActive,
  companyId: 'company-1',
);

void main() {
  group('spreadsheet access is admin only', () {
    test('an admin may use the spreadsheet', () {
      expect(canUseSpreadsheet(_user(UserRole.admin)), isTrue);
    });

    test('an owner role, which is the admin role here, may use it', () {
      // The application models the business owner as UserRole.admin.
      final owner = _user(UserRole.admin);
      expect(canUseSpreadsheet(owner), isTrue);
      expect(owner.can(spreadsheetPermission), isTrue);
    });

    test('a secretary may not use the spreadsheet', () {
      expect(canUseSpreadsheet(_user(UserRole.secretary)), isFalse);
    });

    test('a signed out user may not use the spreadsheet', () {
      expect(canUseSpreadsheet(null), isFalse);
    });

    test('the rule uses an existing admin only permission', () {
      // No new permission is introduced: this one already exists and is
      // already denied to a secretary.
      expect(spreadsheetPermission, AppPermission.administerDatabase);
      expect(_user(UserRole.secretary).can(spreadsheetPermission), isFalse);
      expect(_user(UserRole.admin).can(spreadsheetPermission), isTrue);
    });

    test('secretary permissions are unchanged by this feature', () {
      final secretary = _user(UserRole.secretary);
      // The weighing workflow a secretary relies on is untouched.
      expect(secretary.can(AppPermission.receiveDeliveries), isTrue);
      expect(secretary.can(AppPermission.viewTodaysRecords), isTrue);
      expect(secretary.can(AppPermission.correctDeliveries), isTrue);
      // And they still cannot manage the database.
      expect(secretary.can(AppPermission.administerDatabase), isFalse);
      expect(secretary.can(AppPermission.manageUsers), isFalse);
    });

    test('an admin keeps every existing permission', () {
      final admin = _user(UserRole.admin);
      for (final permission in AppPermission.values) {
        expect(admin.can(permission), isTrue, reason: permission.name);
      }
    });
  });
}
