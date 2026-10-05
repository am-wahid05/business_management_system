import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/auth/active_company_context.dart';
import 'package:flutter_application_2/features/auth/account_service.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/auth/auth_repository.dart';
import 'package:flutter_application_2/features/auth/login_screen.dart';
import 'package:flutter_application_2/features/auth/supabase_auth_repository.dart';
import 'package:flutter_application_2/features/backup/backup_service.dart';
import 'package:flutter_application_2/features/company/company_branding.dart';
import 'package:flutter_application_2/features/management/settings_screen.dart';
import 'package:flutter_application_2/features/receiving/paper_size.dart';
import 'package:flutter_application_2/features/receiving/print_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('Supabase login repository', () {
    test('sends credentials to the Supabase Auth password endpoint', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'msg': 'Invalid login credentials'}),
            400,
          );
        }),
      );
      final repository = SupabaseAuthRepository(client);

      await expectLater(
        repository.signIn('localtest', 'localtest123'),
        throwsA(isA<StateError>()),
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/auth/v1/token');
      expect(requests.single.url.queryParameters['grant_type'], 'password');
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['email'], 'localtest');
      expect(body['password'], 'localtest123');
      await repository.dispose();
      await client.dispose();
    });

    test('restoring without a session clears cached print context', () async {
      final context = ActiveCompanyContext(
        const AppUser(
          id: 'user-a',
          username: 'a@example.com',
          displayName: 'Company A User',
          role: UserRole.admin,
          isActive: true,
          companyId: 'company-a',
        ),
      );
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
      );
      final repository = SupabaseAuthRepository(
        client,
        activeCompanyContext: context,
      );
      addTearDown(PrintPreferences.clear);
      addTearDown(repository.dispose);
      addTearDown(client.dispose);
      PrintPreferences.clear();
      PrintPreferences.remember(
        'company-a',
        const CompanyPrintProfile(receiptPaper: PaperSize.thermal58),
      );
      PrintPreferences.rememberContext(context);

      await repository.restoreSession();

      expect(context.value, isNull);
      final profile = await PrintPreferences.current(context: context);
      expect(profile.receiptPaper, PaperSize.thermal80);
    });
  });

  testWidgets(
    'remote login UI submits entered credentials and has no local demo path',
    (tester) async {
      final repository = _RemoteAuthRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: false,
            splashFactory: InkRipple.splashFactory,
          ),
          home: LoginScreen(authRepository: repository),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email address'), findsOneWidget);
      expect(find.textContaining('LOCAL TEST'), findsNothing);
      expect(find.text('Login as Admin'), findsNothing);

      await tester.enterText(find.byType(TextFormField).first, 'localtest');
      await tester.enterText(find.byType(TextFormField).last, 'localtest123');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(repository.lastIdentifier, 'localtest');
      expect(repository.lastPassword, 'localtest123');
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
    },
  );

  testWidgets('login shows the active company branding', (tester) async {
    final context = ActiveCompanyContext(
      const AppUser(
        id: 'user-1',
        username: 'user@example.com',
        displayName: 'Company Admin',
        role: UserRole.admin,
        isActive: true,
        companyId: 'company-1',
        companyName: 'Harbor Cooperative',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authRepository: _RemoteAuthRepository(),
          activeCompanyContext: context,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Harbor Cooperative'), findsOneWidget);
    expect(find.text('AL-BNC Ventures'), findsNothing);
  });

  testWidgets('selected membership determines the dashboard role', (
    tester,
  ) async {
    final repository = _RemoteAuthRepository()
      ..signInResult = const AppUser(
        id: 'user-1',
        username: 'user@example.com',
        displayName: 'Member',
        role: UserRole.admin,
        isActive: true,
        companyId: 'company-admin',
        companyName: 'Admin Company',
      )
      ..memberships = const [
        CompanyMembership(
          companyId: 'company-admin',
          companyName: 'Admin Company',
          role: UserRole.admin,
        ),
        CompanyMembership(
          companyId: 'company-secretary',
          companyName: 'Secretary Company',
          role: UserRole.secretary,
        ),
      ];
    AppUser? authenticatedUser;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authRepository: repository,
          onAuthenticated: (user) async => authenticatedUser = user,
        ),
        routes: {
          '/admin': (_) => const Text('Admin dashboard'),
          '/secretary': (_) => const Text('Secretary dashboard'),
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'Password1');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a company'), findsOneWidget);
    await tester.tap(find.text('Secretary Company'));
    await tester.pumpAndSettle();

    expect(repository.selectedCompanyId, 'company-secretary');
    expect(authenticatedUser?.role, UserRole.secretary);
    expect(authenticatedUser?.companyId, 'company-secretary');
    expect(find.text('Secretary dashboard'), findsOneWidget);
  });

  testWidgets('settings exposes company branding and change password', (
    tester,
  ) async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(':memory:');
    final context = ActiveCompanyContext(
      const AppUser(
        id: 'user-1',
        username: 'user@example.com',
        displayName: 'Company Admin',
        role: UserRole.admin,
        isActive: true,
        companyId: 'company-1',
        companyName: 'Harbor Cooperative',
      ),
    );
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
    );
    addTearDown(database.close);
    addTearDown(client.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          backupService: BackupService(database),
          accountService: _FakeAccountService(),
          brandingService: CompanyBrandingService(client, context),
          activeCompanyContext: context,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Company branding'), findsOneWidget);
    expect(find.text('Change Password'), findsOneWidget);
    expect(find.text('Harbor Cooperative'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _RemoteAuthRepository implements AuthRepository {
  final ActiveCompanyContext _context = ActiveCompanyContext();
  String? lastIdentifier;
  String? lastPassword;
  AppUser? signInResult;
  List<CompanyMembership> memberships = const [];
  String? selectedCompanyId;

  @override
  ActiveCompanyContext get activeCompanyContext => _context;

  @override
  AppUser? get currentUser => _context.value;

  @override
  bool get isRemote => true;

  @override
  Future<List<AppUser>> allUsers() async => const [];

  @override
  Future<bool> hasUsers() async => true;

  @override
  Future<void> restoreSession() async {}

  @override
  Future<AppUser?> signIn(String identifier, String password) async {
    lastIdentifier = identifier;
    lastPassword = password;
    _context.value = signInResult;
    return signInResult;
  }

  @override
  Future<List<CompanyMembership>> companiesForCurrentUser() async =>
      memberships;

  @override
  Future<void> selectCompany(String companyId) async {
    selectedCompanyId = companyId;
    final current = _context.value!;
    final membership = memberships.singleWhere(
      (item) => item.companyId == companyId,
    );
    _context.value = current.copyWith(
      companyId: membership.companyId,
      companyName: membership.companyName,
      companyLogoPath: membership.logoPath,
      clearCompanyLogoPath: membership.logoPath == null,
      role: membership.role,
    );
  }

  @override
  Future<AppUser> createUser({
    required String username,
    required String displayName,
    required UserRole role,
    required String password,
  }) => throw StateError('Remote login must not create a local account.');

  @override
  Future<void> signOut() async => _context.value = null;
}

class _FakeAccountService implements AccountService {
  @override
  bool get isAvailable => true;

  @override
  String? get currentEmail => 'user@example.com';

  @override
  bool get isRecovering => false;

  @override
  Stream<bool> get recoveryEvents => const Stream<bool>.empty();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> sendPasswordResetEmail(String address) async {}

  @override
  Future<void> resetPassword(String newPassword) async {}

  @override
  Future<void> cancelRecovery() async {}
}
