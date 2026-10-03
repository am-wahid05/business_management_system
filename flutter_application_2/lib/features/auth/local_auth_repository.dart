import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_models.dart';
import 'active_company_context.dart';
import 'auth_repository.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(
    this.database, {
    PasswordHasher? hasher,
    ActiveCompanyContext? activeCompanyContext,
  }) : _hasher = hasher ?? const Pbkdf2PasswordHasher(),
       _activeCompanyContext = activeCompanyContext ?? ActiveCompanyContext();

  final Database database;
  final PasswordHasher _hasher;
  final ActiveCompanyContext _activeCompanyContext;

  @override
  ActiveCompanyContext get activeCompanyContext => _activeCompanyContext;

  @override
  AppUser? get currentUser => _activeCompanyContext.value;

  @override
  bool get isRemote => false;

  @override
  Future<void> restoreSession() async {}

  @override
  Future<bool> hasUsers() async {
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM users',
    );
    return (result.single['count']! as int) > 0;
  }

  @override
  Future<AppUser> createUser({
    required String username,
    required String displayName,
    required UserRole role,
    required String password,
    String? companyName,
  }) async {
    _validateCredentials(username, displayName, password);
    final salt = _randomBytes(16);
    final hash = await _hasher.hash(password, salt);
    final now = DateTime.now().toIso8601String();
    final user = AppUser(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      username: username.trim(),
      displayName: displayName.trim(),
      role: role,
      isActive: true,
    );
    var bootstrapUser = false;
    try {
      await database.transaction((transaction) async {
        final existing = await transaction.rawQuery(
          'SELECT COUNT(*) AS count FROM users',
        );
        final hasExistingUsers = (existing.single['count']! as int) > 0;
        if (hasExistingUsers &&
            !(currentUser?.can(AppPermission.manageUsers) ?? false)) {
          throw StateError('Only an administrator can create users');
        }
        bootstrapUser = !hasExistingUsers;
        await transaction.insert('users', {
          'id': user.id,
          'username': user.username,
          'display_name': user.displayName,
          'role': user.role.name,
          'password_hash': hash,
          'password_salt': base64UrlEncode(salt),
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError())
        throw StateError('That username is already in use');
      rethrow;
    }
    if (bootstrapUser) _activeCompanyContext.value = user;
    return user;
  }

  @override
  Future<AppUser?> signIn(String username, String password) async {
    final rows = await database.query(
      'users',
      where: 'username = ? AND is_active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final valid = await _hasher.verify(
      password,
      row['password_salt']! as String,
      row['password_hash']! as String,
    );
    if (!valid) return null;
    final user = _fromRow(row);
    _activeCompanyContext.value = user;
    return user;
  }

  @override
  Future<List<CompanyMembership>> companiesForCurrentUser() async => const [];

  @override
  Future<void> selectCompany(String companyId) async {}

  @override
  Future<List<AppUser>> allUsers() async {
    final rows = await database.query(
      'users',
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> signOut() async {
    _activeCompanyContext.value = null;
  }

  static AppUser _fromRow(Map<String, Object?> row) => AppUser(
    id: row['id']! as String,
    username: row['username']! as String,
    displayName: row['display_name']! as String,
    role: UserRole.values.byName(row['role']! as String),
    isActive: row['is_active'] == 1,
  );

  static void _validateCredentials(
    String username,
    String displayName,
    String password,
  ) {
    if (username.trim().length < 3)
      throw ArgumentError('Username must contain at least 3 characters');
    if (displayName.trim().isEmpty)
      throw ArgumentError('Display name is required');
    if (password.length < 8)
      throw ArgumentError('Password must contain at least 8 characters');
  }

  static List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => Random.secure().nextInt(256));
}

abstract interface class PasswordHasher {
  Future<String> hash(String password, List<int> salt);
  Future<bool> verify(String password, String encodedSalt, String expectedHash);
}

class Pbkdf2PasswordHasher implements PasswordHasher {
  const Pbkdf2PasswordHasher();

  static final _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 120000,
    bits: 256,
  );

  @override
  Future<String> hash(String password, List<int> salt) async {
    final key = await _algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return base64UrlEncode(await key.extractBytes());
  }

  @override
  Future<bool> verify(
    String password,
    String encodedSalt,
    String expectedHash,
  ) async {
    final actual = await hash(password, base64Url.decode(encodedSalt));
    return _constantTimeEquals(actual, expectedHash);
  }

  static bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
