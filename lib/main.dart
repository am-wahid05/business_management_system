import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/albnc_app.dart';
import 'app/supabase_config.dart';
import 'features/auth/account_service.dart';
import 'features/products/product_database.dart';
import 'features/products/product_repository.dart';
import 'features/receiving/delivery_repository.dart';
import 'features/auth/auth_models.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/local_auth_repository.dart';
import 'features/auth/supabase_auth_repository.dart';
import 'features/auth/supabase_auth_link_handler.dart';
import 'features/company/company_branding.dart';
import 'features/receiving/print_settings_service.dart';
import 'features/receiving/receiving_service.dart';
import 'features/suppliers/supplier_repository.dart';
import 'features/sync/supabase_delivery_store.dart';
import 'features/sync/sync_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await ProductDatabase.open();
  late final AuthRepository authRepository;
  AccountService? accountService;
  SupabaseAuthLinkHandler? authLinkHandler;
  CompanyBrandingService? brandingService;
  SupabaseClient? subscriptionClient;

  if (SupabaseConfig.useLocalAuth) {
    final localRepository = LocalAuthRepository(database);
    authRepository = localRepository;
    await _seedLocalDemoUsers(localRepository);
  } else {
    if (SupabaseConfig.authMode != 'supabase') {
      runApp(const _AuthStartupErrorApp());
      return;
    }

    try {
      authLinkHandler = SupabaseAuthLinkHandler();
      // Supabase must remain the first owner of the cold-start stream so its
      // official PKCE exchange cannot be missed. The observer starts after
      // initialization and also reads the initial URI for safe error handling.
      final client = await SupabaseConfig.initialize();
      if (client == null) {
        runApp(const _AuthStartupErrorApp());
        return;
      }
      await authLinkHandler.start();
      final repository = SupabaseAuthRepository(
        client,
        authLinkHandler: authLinkHandler,
      );
      subscriptionClient = client;
      authRepository = repository;
      accountService = SupabaseAccountService(
        client,
        authLinkHandler: authLinkHandler,
      );
      brandingService = CompanyBrandingService(
        client,
        repository.activeCompanyContext,
      );
      await repository.restoreSession();
      // Screens that print resolve the active company's paper sizes through
      // this client without every one of them being handed it. It holds a
      // connection, never a credential: reads are made with the signed-in
      // session and re-checked by the same company RLS as the company row
      // itself, so this cannot reach a company the user is not part of.
      PrintPreferences.attachClient(client);
      PrintPreferences.rememberContext(repository.activeCompanyContext);
    } catch (_) {
      // Never switch to local credentials when remote initialization fails.
      runApp(const _AuthStartupErrorApp());
      return;
    }
  }

  // Local installations are a single-company database and do not have a
  // tenant ID. When the remote auth path is active, scope repositories to the
  // selected company in the shared auth context.
  final String? Function()? companyIdProvider = authRepository.isRemote
      ? () => authRepository.activeCompanyContext.companyId
      : null;
  final productRepository = ProductRepository(
    database,
    companyIdProvider: companyIdProvider,
  );
  final deliveryRepository = DeliveryRepository(
    database,
    companyIdProvider: companyIdProvider,
    userIdProvider: () => authRepository.currentUser?.id,
  );
  await productRepository.seedInitialProducts();
  final supplierRepository = SupplierRepository(
    database: database,
    companyIdProvider: companyIdProvider,
  );
  await supplierRepository.initialize();
  SyncCoordinator? syncCoordinator;
  if (authRepository.isRemote && subscriptionClient != null) {
    final client = subscriptionClient;
    syncCoordinator = SyncCoordinator(
      database: database,
      deliveryRepository: deliveryRepository,
      remoteStore: SupabaseDeliveryStore(
        client,
        localDatabase: database,
        userId: () => authRepository.currentUser?.id,
        isAdmin: () => authRepository.currentUser?.role == UserRole.admin,
      ),
      onDownloaded: () async {
        await productRepository.seedInitialProducts();
        await supplierRepository.initialize();
      },
    );
  }
  runApp(
    AlbncApp(
      productRepository: productRepository,
      deliveryRepository: deliveryRepository,
      authRepository: authRepository,
      accountService: accountService,
      authLinkHandler: authLinkHandler,
      brandingService: brandingService,
      subscriptionClient: subscriptionClient,
      syncCoordinator: syncCoordinator,
      onAuthenticated: (_) async {
        await productRepository.seedInitialProducts();
        await supplierRepository.initialize();
      },
      repository: supplierRepository,
      receivingService: ReceivingService(
        database: database,
        supplierRepository: supplierRepository,
        companyIdProvider: companyIdProvider,
        userIdProvider: () => authRepository.currentUser?.id,
      ),
    ),
  );
}

Future<void> _seedLocalDemoUsers(LocalAuthRepository authRepository) async {
  final users = await authRepository.allUsers();
  if (!users.any(
    (user) => user.username.toLowerCase() == LocalAuthRepository.testUsername,
  )) {
    await authRepository.createUser(
      username: LocalAuthRepository.testUsername,
      displayName: 'Local Test Admin',
      role: UserRole.admin,
      password: LocalAuthRepository.testPassword,
    );
  }
  if (!users.any(
    (user) =>
        user.username.toLowerCase() ==
        LocalAuthRepository.testSecretaryUsername,
  )) {
    await authRepository.createUser(
      username: LocalAuthRepository.testSecretaryUsername,
      displayName: 'Local Test Secretary',
      role: UserRole.secretary,
      password: LocalAuthRepository.testSecretaryPassword,
    );
  }
}

class _AuthStartupErrorApp extends StatelessWidget {
  const _AuthStartupErrorApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Supabase authentication could not start. Check the app's "
            'Supabase URL, publishable key, and network connection. '
            'Local demo sign-in is disabled in this mode.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
