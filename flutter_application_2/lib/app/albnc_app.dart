import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/active_company_context.dart';
import '../features/auth/auth_models.dart';
import '../features/auth/auth_repository.dart';
import '../features/auth/no_access_screen.dart';
import '../features/auth/user_management_screen.dart';
import '../features/management/admin_dashboard_screen.dart';
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
import '../features/backup/backup_service.dart';
import '../features/company/company_branding.dart';
import '../features/suppliers/supplier_statements_screen.dart';
import '../features/assistant/business_assistant_screen.dart';
import '../features/assistant/business_assistant_service.dart';
import 'app_routes.dart';
import 'app_theme.dart';

class AlbncApp extends StatelessWidget {
  AlbncApp({
    required this.productRepository,
    required this.deliveryRepository,
    required this.authRepository,
    ActiveCompanyContext? activeCompanyContext,
    this.brandingService,
    this.onAuthenticated,
    SyncStatusRepository? syncStatusRepository,
    this.syncCoordinator,
    DailyReportRepository? reportRepository,
    AnalyticsRepository? analyticsRepository,
    SupplierRepository? repository,
    ReceivingService? receivingService,
    super.key,
  }) : activeCompanyContext =
           activeCompanyContext ?? authRepository.activeCompanyContext,
       repository =
           repository ??
           SupplierRepository(
             database: deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.currentUser?.companyId
                 : null,
           ),
       reportRepository =
           reportRepository ?? DailyReportRepository(deliveryRepository),
       analyticsRepository =
           analyticsRepository ??
           AnalyticsRepository(
             deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.currentUser?.companyId
                 : null,
           ),
       syncStatusRepository =
           syncStatusRepository ??
           SyncStatusRepository(
             deliveryRepository.database,
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.currentUser?.companyId
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
                       ? () => authRepository.currentUser?.companyId
                       : null,
                 ),
             companyIdProvider: authRepository.isRemote
                 ? () => authRepository.currentUser?.companyId
                 : null,
             userIdProvider: () => authRepository.currentUser?.id,
           );

  final SupplierRepository repository;
  final ProductRepository productRepository;
  final DeliveryRepository deliveryRepository;
  final DailyReportRepository reportRepository;
  final AnalyticsRepository analyticsRepository;
  final AuthRepository authRepository;
  final ActiveCompanyContext activeCompanyContext;
  final CompanyBrandingService? brandingService;
  final Future<void> Function(AppUser user)? onAuthenticated;
  final SyncStatusRepository syncStatusRepository;
  final SyncCoordinator? syncCoordinator;
  final ReceivingService receivingService;

  Widget _protected(
    Widget screen, {
    UserRole? role,
    AppPermission? permission,
  }) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: activeCompanyContext,
      builder: (context, user, _) {
        if (user == null)
          return LoginScreen(
            authRepository: authRepository,
            activeCompanyContext: activeCompanyContext,
            brandingService: brandingService,
            onAuthenticated: onAuthenticated,
          );
        if ((role != null && user.role != role) ||
            (permission != null && !user.can(permission)))
          return const NoAccessScreen();
        return screen;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: activeCompanyContext,
      builder: (context, user, _) => MaterialApp(
        key: ValueKey(
          '${user?.id ?? 'signed-out'}:${user?.companyId ?? 'none'}',
        ),
        title: user?.companyName ?? 'Company Management',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        initialRoute: user == null
            ? AppRoutes.login
            : user.role == UserRole.admin
            ? AppRoutes.adminDashboard
            : AppRoutes.secretaryDashboard,
        routes: {
          AppRoutes.login: (_) => LoginScreen(
            authRepository: authRepository,
            activeCompanyContext: activeCompanyContext,
            brandingService: brandingService,
            onAuthenticated: onAuthenticated,
          ),
          AppRoutes.secretaryDashboard: (_) => _protected(
            SecretaryDashboardScreen(
              statusRepository: syncStatusRepository,
              onLogout: authRepository.signOut,
              coordinator: syncCoordinator,
              activeCompanyContext: activeCompanyContext,
              authRepository: authRepository,
              onCompanyChanging: repository.clearForCompanyChange,
              onCompanyChanged: () async {
                await productRepository.seedInitialProducts();
                await repository.initialize();
              },
              brandingService: brandingService,
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
              authRepository: authRepository,
            ),
            permission: AppPermission.viewTodaysRecords,
          ),
          AppRoutes.adminDashboard: (_) => _protected(
            AdminDashboardScreen(
              repository: deliveryRepository,
              analyticsRepository: analyticsRepository,
              userName: authRepository.currentUser?.displayName ?? 'Admin',
              onLogout: authRepository.signOut,
              activeCompanyContext: activeCompanyContext,
              authRepository: authRepository,
              onCompanyChanging: repository.clearForCompanyChange,
              onCompanyChanged: () async {
                await productRepository.seedInitialProducts();
                await repository.initialize();
              },
              brandingService: brandingService,
            ),
            role: UserRole.admin,
          ),
          AppRoutes.suppliers: (_) => _protected(
            SuppliersScreen(
              repository: repository,
              deliveryRepository: deliveryRepository,
              onLogout: authRepository.signOut,
              brandingService: brandingService,
              recorderNamesProvider: () async => {
                for (final user in await authRepository.allUsers())
                  user.id: user.displayName,
              },
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
              brandingService: brandingService,
              authRepository: authRepository,
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
              companyNameProvider: () =>
                  activeCompanyContext.companyName ?? 'Company',
              recorderNamesProvider: () async => {
                for (final user in await authRepository.allUsers())
                  user.id: user.displayName,
              },
            ),
            role: UserRole.admin,
          ),
          AppRoutes.excel: (_) => _protected(
            ExcelExportScreen(
              service: ExcelExportService(
                deliveryRepository,
                companyNameProvider: () =>
                    activeCompanyContext.companyName ?? 'Company',
                recorderNamesProvider: () async => {
                  for (final user in await authRepository.allUsers())
                    user.id: user.displayName,
                },
              ),
            ),
            role: UserRole.admin,
          ),
          AppRoutes.excelImport: (_) => _protected(
            ExcelImportScreen(
              service: ExcelImportService(
                database: deliveryRepository.database,
                deliveryRepository: deliveryRepository,
                userId: authRepository.currentUser?.id ?? 'unknown',
                companyIdProvider: () => authRepository.currentUser?.companyId,
                receivingService: receivingService,
              ),
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
                    ? () => authRepository.currentUser?.companyId
                    : null,
              ),
              brandingService: brandingService,
              activeCompanyContext: activeCompanyContext,
            ),
            permission: AppPermission.configureSystem,
          ),
          AppRoutes.assistant: (_) => _protected(
            BusinessAssistantScreen(
              service: BusinessAssistantService(analyticsRepository),
            ),
            role: UserRole.admin,
          ),
        },
      ),
    );
  }
}
