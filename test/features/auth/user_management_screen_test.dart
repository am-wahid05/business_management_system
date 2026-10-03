import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/auth/active_company_context.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/auth/auth_repository.dart';
import 'package:flutter_application_2/features/auth/user_management_screen.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this.user);

  final AppUser user;
  String? createdEmail;
  String? createdDisplayName;
  UserRole? createdRole;
  String? createdPassword;
  int createUserCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  ActiveCompanyContext get activeCompanyContext => throw UnimplementedError();

  @override
  AppUser? get currentUser => user;

  @override
  bool get isRemote => true;

  @override
  Future<List<AppUser>> allUsers() async => [user];

  @override
  Future<AppUser> createUser({
    required String username,
    required String displayName,
    required UserRole role,
    required String password,
    String? companyName,
  }) async {
    createUserCalls++;
    createdEmail = username;
    createdDisplayName = displayName;
    createdRole = role;
    createdPassword = password;
    return AppUser(
      id: 'new-user',
      username: username,
      displayName: displayName,
      role: role,
      isActive: true,
    );
  }
}

AppUser _admin() => AppUser(
  id: 'admin-1',
  username: 'admin@example.com',
  displayName: 'Owner',
  role: UserRole.admin,
  isActive: true,
  companyId: 'company-1',
  companyName: 'Test Company',
);

Future<void> _openDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: UserManagementScreen(repository: _FakeAuthRepository(_admin())),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add user'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'add user dialog labels the field Email and keeps secretary default',
    (tester) async {
      await _openDialog(tester);

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
      expect(find.text('Display name'), findsOneWidget);
      expect(find.text('Temporary password'), findsOneWidget);
      expect(find.text('secretary'), findsOneWidget);
    },
  );

  testWidgets('invalid email is rejected and no user is created', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(_admin());
    await tester.pumpWidget(
      MaterialApp(home: UserManagementScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.createUserCalls, 0);
  });

  testWidgets('empty email is rejected', (tester) async {
    final repository = _FakeAuthRepository(_admin());
    await tester.pumpWidget(
      MaterialApp(home: UserManagementScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required'), findsOneWidget);
    expect(repository.createUserCalls, 0);
  });

  testWidgets('valid email is sent to createUser as the entered address', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(_admin());
    await tester.pumpWidget(
      MaterialApp(home: UserManagementScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add user'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'secretary@example.com');
    await tester.tap(find.text('Create user'));
    await tester.pumpAndSettle();

    expect(repository.createUserCalls, 1);
    expect(repository.createdEmail, 'secretary@example.com');
    expect(repository.createdRole, UserRole.secretary);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
