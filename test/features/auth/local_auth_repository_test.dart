import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/auth/local_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late LocalAuthRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    database = await databaseFactoryFfi.openDatabase(':memory:', options: OpenDatabaseOptions(version: 1, onCreate: (database, version) async {
      await database.execute('''
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
    }));
    repository = LocalAuthRepository(database);
  });

  tearDown(() => database.close());

  test('stores a salted hash and authenticates the correct password only', () async {
    final created = await repository.createUser(username: 'owner', displayName: 'Owner', role: UserRole.admin, password: 'secure-pass');
    final row = (await database.query('users')).single;

    expect(created.role, UserRole.admin);
    expect(row['password_hash'], isNot('secure-pass'));
    expect(row['password_salt'], isNotEmpty);
    expect(await repository.signIn('owner', 'wrong-pass'), isNull);
    expect((await repository.signIn('owner', 'secure-pass'))!.id, created.id);
  });

  test('enforces role permissions', () async {
    await repository.createUser(username: 'secretary', displayName: 'Secretary', role: UserRole.secretary, password: 'secure-pass');
    final user = await repository.signIn('secretary', 'secure-pass');

    expect(user!.can(AppPermission.receiveDeliveries), isTrue);
    expect(user.can(AppPermission.lookupSuppliers), isTrue);
    expect(user.can(AppPermission.viewTodaysRecords), isTrue);
    expect(user.can(AppPermission.manageUsers), isFalse);
    expect(user.can(AppPermission.administerDatabase), isFalse);
    expect(user.can(AppPermission.configureSystem), isFalse);
    expect(user.can(AppPermission.unrestrictedDeletion), isFalse);
  });

  test('rejects duplicate usernames and inactive users', () async {
    await repository.createUser(username: 'owner', displayName: 'Owner', role: UserRole.admin, password: 'secure-pass');
    expect(() => repository.createUser(username: 'OWNER', displayName: 'Other', role: UserRole.admin, password: 'secure-pass'), throwsStateError);
    await database.update('users', {'is_active': 0}, where: 'username = ?', whereArgs: ['owner']);
    expect(await repository.signIn('owner', 'secure-pass'), isNull);
  });
}
