import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/account_service.dart';
import '../features/auth/account_settings_screen.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/company/company_branding.dart';
import '../features/auth/no_access_screen.dart';
import '../features/auth/user_management_screen.dart';
import '../features/management/admin_dashboard_screen.dart';
import '../features/about/about_screen.dart';
import '../features/management/excel_export_screen.dart';
import '../features/management/excel_import_screen.dart';
import '../features/management/products_screen.dart';
import '../features/management/settings_screen.dart';
import '../features/management/suppliers_screen.dart';
import '../features/secretary/new_receiving_screen.dart';
import '../features/secretary/secretary_dashboard_screen.dart';
import '../features/secretary/todays_records_screen.dart';
import '../features/sync/sync_coordinator.dart';
import '../features/sync/sync_status_repository.dart';
import '../features/suppliers/supplier_repository.dart';
import '../features/products/product_repository.dart';
import '../features/receiving/delivery_repository.dart';
import '../features/receiving/receiving_service.dart';
import '../features/reports/daily_report_repository.dart';
import '../features/analytics/analytics_repository.dart';
import '../features/analytics/analytics_models.dart';
import '../features/analytics/analytics_report_screen.dart';
import '../features/exports/excel_export_service.dart';
import '../features/imports/excel_import_service.dart';
import '../features/imports/workbook_grid_store.dart';
import '../features/management/workbook_grid_screen.dart';
import '../features/backup/backup_service.dart';
import '../features/credits/sms_credit_service.dart';
import '../features/subscriptions/billing_screen.dart';
import '../features/subscriptions/entitlement_service.dart';
import '../features/spreadsheet/spreadsheet_controller.dart';
import '../features/spreadsheet/spreadsheet_service.dart';
import '../features/spreadsheet/spreadsheet_state_store.dart';
import '../features/spreadsheet/spreadsheet_screen.dart';
import '../features/suppliers/supplier_statements_screen.dart';
import '../features/assistant/business_assistant_screen.dart';
import '../features/assistant/business_assistant_service.dart';
import 'app_routes.dart';
import 'app_theme.dart';
import 'password_recovery_gate.dart';

class AlbncApp extends StatelessWidget {
  AlbncApp({
    required this.productRepository,
    required this.deliveryRepository,
    required this.authRepository,
    this.accountService,
    this.brandingService,
    this.subscriptionClient,
    this.onAuthenticated,
    SyncStatusRepository? syncStatusRepository,
    this.syncCoordinator,
    DailyReportRepository? reportRepository,
    AnalyticsRepository? analyticsRepository,
    SupplierRepository? repository,
    ReceivingService? receivingService,
    super.key,
  }) : repository =
           repository ??
           SupplierRepository(
             database: deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.activeCompanyContext.companyId
                 : null,
           ),
       reportRepository =
           reportRepository ?? DailyReportRepository(deliveryRepository),
       analyticsRepository =
           analyticsRepository ??
           AnalyticsRepository(
             deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.activeCompanyContext.companyId
                 : null,
           ),
       syncStatusRepository =
           syncStatusRepository ??
           SyncStatusRepository(
             deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.activeCompanyContext.companyId
                 : null,
           ),
       receivingService =
           receivingService ??
           ReceivingService(
             database: deliveryRepository.database,
             supplierRepository:
                 repository ??
                 SupplierRepository(
                   database: deliveryRepository.database,
                   companyIdProvider: authRepository.isRemote
                       ? () => authRepository.activeCompanyContext.companyId
                       : null,
                 ),
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.activeCompanyContext.companyId
                 : null,
             userIdProvider: () => authRepository.currentUser?.id,
           );

  final SupplierRepository repository;
  final ProductRepository productRepository;
  final DeliveryRepository deliveryRepository;
  final DailyReportRepository reportRepository;
  final AnalyticsRepository analyticsRepository;
  final AuthRepository authRepository;
  final AccountService? accountService;
  final CompanyBrandingService? brandingService;
  final SupabaseClient? subscriptionClient;
  final Future<void> Function(AppUser user)? onAuthenticated;
  final SyncStatusRepository syncStatusRepository;
  final SyncCoordinator? syncCoordinator;
  final ReceivingService receivingService;

  Widget _protected(
    Widget screen, {
    UserRole? role,
    AppPermission? permission,
  }) {
    final user = authRepository.currentUser;
    if (user == null ||
        (role != null && user.role != role) ||
        (permission != null && !user.can(permission))) {
      return const NoAccessScreen();
    }
    return screen;
  }

  @override
  Widget build(BuildContext context) {
    // The active company scope for every repository below. This mirrors the
    // inline form already used by the other routes in this table, and stays
    // null in a local single-company installation, which has no tenant id.
    final String? Function()? companyIdProvider = authRepository.isRemote
        ? () => authRepository.activeCompanyContext.companyId
        : null;
    return PasswordRecoveryGate(
      accountService: accountService,
      child: MaterialApp(
        title: 'Business Management System',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: AppRoutes.login,
        routes: {
          AppRoutes.login: (_) => LoginScreen(
            authRepository: authRepository,
            accountService: accountService,
            activeCompanyContext: authRepository.activeCompanyContext,
            brandingService: brandingService,
            onAuthenticated: onAuthenticated,
            // Registration only exists when there is a remote identity
            // provider. In the local setup the accounts are seeded, so no
            // sign-up link is offered at all.
            signUpService: subscriptionClient == null
                ? null
                : SupabaseSignUpService(subscriptionClient!),
          ),
          AppRoutes.resetPassword: (_) => accountService == null
              ? const NoAccessScreen()
              : ResetPasswordScreen(accountService: accountService!),
          AppRoutes.secretaryDashboard: (_) => _protected(
            SecretaryDashboardScreen(
              statusRepository: syncStatusRepository,
              onLogout: authRepository.signOut,
              coordinator: syncCoordinator,
              activeCompanyContext: authRepository.activeCompanyContext,
              authRepository: authRepository,
              brandingService: brandingService,
              creditService: subscriptionClient == null
                  ? null
                  : SmsCreditService(subscriptionClient!),
              onCompanyChanging: repository.clearForCompanyChange,
              onCompanyChanged: () async {
                await productRepository.seedInitialProducts();
                await repository.initialize();
                final user = authRepository.currentUser;
                if (user != null && context.mounted) {
                  Navigator.of(context).pushReplacementNamed(
                    user.role == UserRole.admin
                        ? AppRoutes.adminDashboard
                        : AppRoutes.secretaryDashboard,
                  );
                }
              },
            ),
            permission: AppPermission.viewTodaysRecords,
          ),
          AppRoutes.newReceiving: (_) => _protected(
            NewReceivingScreen(
              repository: repository,
              productRepository: productRepository,
              deliveryRepository: deliveryRepository,
              receivingService: receivingService,
            ),
            permission: AppPermission.receiveDeliveries,
          ),
          AppRoutes.todaysRecords: (_) => _protected(
            TodaysRecordsScreen(
              repository: deliveryRepository,
              statusRepository: syncStatusRepository,
              coordinator: syncCoordinator,
              brandingService: brandingService,
              activeCompanyContext: authRepository.activeCompanyContext,
              authRepository: authRepository,
              supabaseClient: subscriptionClient,
              creditService: subscriptionClient == null
                  ? null
                  : SmsCreditService(subscriptionClient!),
            ),
            permission: AppPermission.viewTodaysRecords,
          ),
          AppRoutes.adminDashboard: (_) => _protected(
            AdminDashboardScreen(
              repository: deliveryRepository,
              analyticsRepository: analyticsRepository,
              userName: authRepository.currentUser?.displayName ?? 'Admin',
              onLogout: authRepository.signOut,
              activeCompanyContext: authRepository.activeCompanyContext,
              authRepository: authRepository,
              brandingService: brandingService,
              creditService: subscriptionClient == null
                  ? null
                  : SmsCreditService(subscriptionClient!),
              onCompanyChanging: repository.clearForCompanyChange,
              onCompanyChanged: () async {
                await productRepository.seedInitialProducts();
                await repository.initialize();
                final user = authRepository.currentUser;
                if (user != null && context.mounted) {
                  Navigator.of(context).pushReplacementNamed(
                    user.role == UserRole.admin
                        ? AppRoutes.adminDashboard
                        : AppRoutes.secretaryDashboard,
                  );
                }
              },
            ),
            role: UserRole.admin,
          ),
          AppRoutes.suppliers: (_) => _protected(
            SuppliersScreen(
              repository: repository,
              deliveryRepository: deliveryRepository,
              activeCompanyContext: authRepository.activeCompanyContext,
              onLogout: authRepository.signOut,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.products: (_) => _protected(
            ProductsScreen(repository: productRepository),
            role: UserRole.admin,
          ),
          AppRoutes.reports: (_) => _protected(
            AnalyticsReportScreen(
              repository: analyticsRepository,
              productRepository: productRepository,
              supplierRepository: repository,
              title: 'Daily Report',
              initialTrend: AnalyticsTrend.daily,
              initialFrom: DateTime.now(),
              initialTo: DateTime.now(),
            ),
            role: UserRole.admin,
          ),
          AppRoutes.analytics: (_) => _protected(
            AnalyticsReportScreen(
              repository: analyticsRepository,
              productRepository: productRepository,
              supplierRepository: repository,
              title: 'Analytics',
              initialTrend: AnalyticsTrend.monthly,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.deliveries: (_) => _protected(
            TodaysRecordsScreen(
              repository: deliveryRepository,
              statusRepository: syncStatusRepository,
              coordinator: syncCoordinator,
              activeCompanyContext: authRepository.activeCompanyContext,
              supabaseClient: subscriptionClient,
              creditService: subscriptionClient == null
                  ? null
                  : SmsCreditService(subscriptionClient!),
            ),
            role: UserRole.admin,
          ),
          AppRoutes.monthlyReports: (_) => _protected(
            AnalyticsReportScreen(
              repository: analyticsRepository,
              productRepository: productRepository,
              supplierRepository: repository,
              title: 'Monthly Report',
              initialTrend: AnalyticsTrend.monthly,
              initialFrom: DateTime(
                DateTime.now().year,
                DateTime.now().month,
                1,
              ),
              initialTo: DateTime.now(),
            ),
            role: UserRole.admin,
          ),
          AppRoutes.yearlyReports: (_) => _protected(
            AnalyticsReportScreen(
              repository: analyticsRepository,
              productRepository: productRepository,
              supplierRepository: repository,
              title: 'Yearly Report',
              initialTrend: AnalyticsTrend.yearly,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.statements: (_) => _protected(
            SupplierStatementsScreen(
              repository: repository,
              deliveryRepository: deliveryRepository,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.excel: (_) => _protected(
            ExcelExportScreen(service: ExcelExportService(deliveryRepository)),
            role: UserRole.admin,
          ),
          AppRoutes.excelImport: (_) => _protected(
            ExcelImportScreen(
              service: ExcelImportService(
                database: deliveryRepository.database,
                deliveryRepository: deliveryRepository,
                userId: authRepository.currentUser?.id ?? 'unknown',
                companyIdProvider: authRepository.isRemote
                    ? () => authRepository.activeCompanyContext.companyId
                    : null,
                receivingService: receivingService,
              ),
              // The grid the user opens from here is saved into the same local
              // database the rest of the app already uses. Without this the screen
              // was handed a store with no database, and Save/Reopen silently did
              // nothing at all.
              //
              // This is the *existing* database, not a second one, so nothing new
              // is opened and no schema is touched: WorkbookGridStore writes into
              // the local_metadata table that ProductDatabase already created.
              gridStore: WorkbookGridStore(deliveryRepository.database),
              // Read on every build so a role or company change is picked up
              // straight away, which is also how the grid learns the company its
              // saved sheets are scoped to.
              currentUser: () => authRepository.currentUser,
            ),
            role: UserRole.admin,
          ),
          // The spreadsheet itself. This sits under the existing Excel area rather
          // than as a new top-level section, so the import screen stays the way in.
          AppRoutes.workbookGrid: (_) => _protected(
            WorkbookGridScreen(
              service: ExcelImportService(
                database: deliveryRepository.database,
                deliveryRepository: deliveryRepository,
                userId: authRepository.currentUser?.id ?? 'unknown',
                companyIdProvider: authRepository.isRemote
                    ? () => authRepository.activeCompanyContext.companyId
                    : null,
                receivingService: receivingService,
              ),
              store: WorkbookGridStore(deliveryRepository.database),
              currentUser: () => authRepository.currentUser,
              supplierRepository: repository,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.users: (_) => _protected(
            UserManagementScreen(repository: authRepository),
            permission: AppPermission.manageUsers,
          ),
          AppRoutes.settings: (_) => _protected(
            SettingsScreen(
              backupService: BackupService(
                deliveryRepository.database,
                companyIdProvider: authRepository.isRemote
                    ? () => authRepository.activeCompanyContext.companyId
                    : null,
              ),
              accountService: accountService,
              brandingService: brandingService,
              activeCompanyContext: authRepository.activeCompanyContext,
            ),
            permission: AppPermission.configureSystem,
          ),
          AppRoutes.assistant: (_) => _protected(
            BusinessAssistantScreen(
              service: BusinessAssistantService(analyticsRepository),
            ),
            role: UserRole.admin,
          ),
          AppRoutes.spreadsheet: (_) => _protected(
            SpreadsheetScreen(
              controller: SpreadsheetController(
                SpreadsheetService(
                  deliveryRepository: deliveryRepository,
                  receivingService: receivingService,
                  userIdProvider: () => authRepository.currentUser?.id,
                  catalogueProvider: productRepository.all,
                ),
                stateStore: SpreadsheetStateStore(deliveryRepository.database),
                companyIdProvider: companyIdProvider,
              ),
              excelImportService: ExcelImportService(
                database: deliveryRepository.database,
                deliveryRepository: deliveryRepository,
                userId: authRepository.currentUser?.id ?? 'unknown',
                companyIdProvider: companyIdProvider,
                receivingService: receivingService,
                catalogueProvider: productRepository.all,
              ),
              currentUser: () => authRepository.currentUser,
              workbookGridStore: WorkbookGridStore(deliveryRepository.database),
              onExport: (rows) async {
                final exportRows = <ExcelExportRow>[];
                for (final row in rows.where((row) => !row.isRemoved)) {
                  final date = row.recordedAt;
                  if (date == null) {
                    throw StateError(
                      'Correct the invalid date on this row before exporting.',
                    );
                  }
                  exportRows.add(
                    ExcelExportRow(
                      date: date,
                      supplierId: row.supplierId,
                      supplierName: row.supplierName,
                      productId: row.productId ?? '',
                      productName: row.productName,
                      numberOfBags: row.numberOfBags,
                      totalWeight: row.totalWeight,
                      recordedBy: row.recorderName,
                      status: row.status,
                      recordType: row.recordType,
                      notes: row.notes,
                    ),
                  );
                }
                final file = await ExcelExportService(
                  deliveryRepository,
                  companyNameProvider: () =>
                      authRepository.activeCompanyContext.companyName ??
                      'Company',
                ).exportGrid(exportRows);
                return 'Spreadsheet exported: ${file.path}';
              },
            ),
            role: UserRole.admin,
          ),
          AppRoutes.billing: (_) => _protected(
            _AdminBillingRoute(
              client: subscriptionClient,
              companyId: () => authRepository.activeCompanyContext.companyId,
            ),
            role: UserRole.admin,
          ),
          // About is read-only application information, so it is available to
          // every signed-in role rather than being gated behind admin. It
          // exposes no company-management controls.
          AppRoutes.about: (_) =>
              _protected(const AboutScreen(), role: UserRole.admin),
          AppRoutes.aboutScreen: (_) => _protected(const AboutScreen()),
          // Account-level settings. Any signed-in user may change their own
          // password; this grants no company-management permission.
          AppRoutes.accountSettings: (_) =>
              _protected(AccountSettingsScreen(accountService: accountService)),
        },
      ),
    );
  }
}

/// Owns the billing services for the lifetime of the route while reusing the
/// existing BillingScreen and preserving the authenticated active company.
class _AdminBillingRoute extends StatefulWidget {
  const _AdminBillingRoute({required this.client, required this.companyId});

  final SupabaseClient? client;
  final String? Function() companyId;

  @override
  State<_AdminBillingRoute> createState() => _AdminBillingRouteState();
}

class _AdminBillingRouteState extends State<_AdminBillingRoute> {
  late final EntitlementService _entitlements;
  late final SmsCreditService _creditService;

  @override
  void initState() {
    super.initState();
    _entitlements = EntitlementService(widget.client);
    _creditService = SmsCreditService(widget.client);
  }

  @override
  void dispose() {
    _entitlements.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BillingScreen(
    entitlements: _entitlements,
    creditService: _creditService,
    companyId: widget.companyId(),
  );
}
