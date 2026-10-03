import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import 'app/albnc_app.dart';
import 'app/supabase_config.dart';
import 'features/auth/active_company_context.dart';
import 'features/company/company_branding.dart';
import 'features/products/product_database.dart';
import 'features/products/product_repository.dart';
import 'features/receiving/delivery_repository.dart';
import 'features/auth/local_auth_repository.dart';
import 'features/auth/auth_models.dart';
import 'features/auth/supabase_auth_repository.dart';
import 'features/receiving/receiving_service.dart';
import 'features/suppliers/supplier_repository.dart';
import 'features/sync/supabase_delivery_store.dart';
import 'features/sync/sync_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabaseClient = await SupabaseConfig.initialize();
  final database = await ProductDatabase.open();
  final activeCompanyContext = ActiveCompanyContext();
  final authRepository = supabaseClient == null
      ? LocalAuthRepository(
          database,
          activeCompanyContext: activeCompanyContext,
        )
      : SupabaseAuthRepository(
          supabaseClient,
          activeCompanyContext: activeCompanyContext,
          readSelectedCompanyId: () async {
            final rows = await database.query(
              'local_metadata',
              where: 'key = ?',
              whereArgs: ['active_company_id'],
              limit: 1,
            );
            return rows.isEmpty ? null : rows.single['value'] as String?;
          },
          writeSelectedCompanyId: (companyId) async {
            await database.insert('local_metadata', {
              'key': 'active_company_id',
              'value': companyId,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          },
        );
  if (supabaseClient != null) await authRepository.restoreSession();
  String? companyIdProvider() => activeCompanyContext.companyId;
  final String? Function()? tenantCompanyIdProvider = supabaseClient == null
      ? null
      : companyIdProvider;
  final productRepository = ProductRepository(
    database,
    companyIdProvider: tenantCompanyIdProvider,
  );
  final supplierRepository = SupplierRepository(
    database: database,
    companyIdProvider: tenantCompanyIdProvider,
  );
  final deliveryRepository = DeliveryRepository(
    database,
    companyIdProvider: tenantCompanyIdProvider,
    userIdProvider: () => authRepository.currentUser?.id,
  );
  final brandingService = supabaseClient == null
      ? null
      : CompanyBrandingService(supabaseClient, activeCompanyContext);
  if (supabaseClient == null || authRepository.currentUser != null) {
    await productRepository.seedInitialProducts();
    await supplierRepository.initialize();
  }
  final syncCoordinator = supabaseClient == null
      ? null
      : SyncCoordinator(
          database: database,
          deliveryRepository: deliveryRepository,
          remoteStore: SupabaseDeliveryStore(
            supabaseClient,
            localDatabase: database,
            companyId: () => activeCompanyContext.companyId,
            userId: () => authRepository.currentUser?.id,
            isAdmin: () => authRepository.currentUser?.role == UserRole.admin,
          ),
          onDownloaded: supplierRepository.initialize,
        );
  runApp(
    AlbncApp(
      productRepository: productRepository,
      deliveryRepository: deliveryRepository,
      authRepository: authRepository,
      activeCompanyContext: activeCompanyContext,
      brandingService: brandingService,
      syncCoordinator: syncCoordinator,
      onAuthenticated: (user) async {
        if (supabaseClient != null && user.companyId == null) {
          throw StateError('Select an active company before continuing.');
        }
        await productRepository.seedInitialProducts();
        await supplierRepository.initialize();
      },
      repository: supplierRepository,
      receivingService: ReceivingService(
        database: database,
        supplierRepository: supplierRepository,
        companyIdProvider: tenantCompanyIdProvider,
        userIdProvider: () => authRepository.currentUser?.id,
      ),
    ),
  );
}
