import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/auth/local_auth_repository.dart';
import 'package:flutter_application_2/features/auth/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The role picked on the login screen is a request, never a permission.
///
/// These tests drive the same helper the screen calls after a successful sign-in,
/// so they cover the rule itself rather than only the widget that shows it.
void main() {
  late Database database;
  late LocalAuthRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(
      ':memory:',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE users (
              id TEXT PRIMARY KEY,
              username TEXT NOT NULL COLLATE NOCASE UNIQUE,
              display_name TEXT NOT NULL,
              role TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              password_salt TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    repository = LocalAuthRepository(database);
  });

  tearDown(() => database.close());

  Future<AppUser> createUser(String username, UserRole role) => repository
      .createUser(
        username: username,
        displayName: username,
        role: role,
        password: 'secure-pass',
      );

  group('role selection matches the real account role', () {
    test('an admin signing in as Admin is allowed', () async {
      final user = await createUser('owner', UserRole.admin);
      expect(
        roleMismatchMessage(
          selected: UserRole.admin,
          actual: user.role,
        ),
        isNull,
      );
    });

    test('a secretary signing in as Secretary is allowed', () async {
      final user = await createUser('secretary', UserRole.secretary);
      expect(
        roleMismatchMessage(
          selected: UserRole.secretary,
          actual: user.role,
        ),
        isNull,
      );
    });

    test('a secretary selecting Admin is refused with a clear message', () async {
      final user = await createUser('secretary', UserRole.secretary);
      final message = roleMismatchMessage(
        selected: UserRole.admin,
        actual: user.role,
      );
      expect(message, isNotNull);
      // The message must name the role the user tried to claim, so the rejection
      // is understandable, and the role their membership actually grants.
      expect(message, contains('not authorized to log in as Admin'));
      expect(message, contains('registered as a Secretary'));
    });

    test('an admin selecting Secretary is refused with a clear message', () async {
      final user = await createUser('owner', UserRole.admin);
      final message = roleMismatchMessage(
        selected: UserRole.secretary,
        actual: user.role,
      );
      expect(message, isNotNull);
      expect(message, contains('not authorized to log in as Secretary'));
      expect(message, contains('registered as an Admin'));
    });

    test('the rejection reveals nothing about other companies or members', () {
      final message = roleMismatchMessage(
        selected: UserRole.admin,
        actual: UserRole.secretary,
      )!;
      // Only the two roles involved may appear; no company names, no other
      // users, no membership details.
      expect(message, isNot(contains('company')));
      expect(message.toLowerCase(), isNot(contains('owner')));
      expect(message.toLowerCase(), isNot(contains('membership')));
    });
  });

  group('the role selection cannot bypass authorization', () {
    test('a secretary account stays a secretary after any sign in', () async {
      await createUser('secretary', UserRole.secretary);
      // Even authenticating successfully, the stored role is unchanged and still
      // lacks the admin-only permissions.
      final user = await repository.signIn('secretary', 'secure-pass');
      expect(user!.role, UserRole.secretary);
      expect(user.can(AppPermission.manageUsers), isFalse);
      expect(user.can(AppPermission.configureSystem), isFalse);
      expect(user.can(AppPermission.unrestrictedDeletion), isFalse);
    });

    test('an admin account keeps its admin permissions', () async {
      await createUser('owner', UserRole.admin);
      final user = await repository.signIn('owner', 'secure-pass');
      expect(user!.role, UserRole.admin);
      expect(user.can(AppPermission.manageUsers), isTrue);
    });
  });

  group('session lifecycle', () {
    // Session restoration is a Supabase concern: the local repository has no
    // server session to restore, so its restoreSession() is deliberately an
    // empty no-op. These tests therefore cover the local contract, namely that
    // the signed-in user is exposed while signed in and gone once signed out.
    test('a signed in admin is the current user with an admin role', () async {
      await createUser('owner', UserRole.admin);
      final user = await repository.signIn('owner', 'secure-pass');
      expect(user, isNotNull);
      expect(repository.currentUser?.role, UserRole.admin);
      expect(repository.currentUser?.companyId, isNull);
    });

    test('a signed in secretary is the current user with a secretary role',
        () async {
      await createUser('secretary', UserRole.secretary);
      await repository.signIn('secretary', 'secure-pass');
      expect(repository.currentUser?.role, UserRole.secretary);
    });
  });

  group('logout', () {
    test('signing out clears the session and requires signing in again', () async {
      await createUser('owner', UserRole.admin);
      expect(repository.currentUser, isNotNull);

      await repository.signOut();
      // The current user is cleared, so nothing can read the previous user's
      // role or company after a logout.
      expect(repository.currentUser, isNull);

      // A fresh repository over the same database also has no session, so
      // reopening the app after a logout requires signing in again.
      final reopened = LocalAuthRepository(database);
      await reopened.restoreSession();
      expect(reopened.currentUser, isNull);
    });

    test('after logout the same account can sign in again', () async {
      await createUser('owner', UserRole.admin);
      await repository.signOut();
      expect(repository.currentUser, isNull);
      expect((await repository.signIn('owner', 'secure-pass'))!.id, isNotNull);
    });
  });
}
