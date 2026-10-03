import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_status_card.dart';
import '../sync/sync_status_repository.dart';
import '../auth/active_company_context.dart';
import '../auth/auth_repository.dart';
import '../company/company_branding.dart';

class SecretaryDashboardScreen extends StatelessWidget {
  const SecretaryDashboardScreen({
    required this.statusRepository,
    required this.onLogout,
    this.coordinator,
    this.activeCompanyContext,
    this.authRepository,
    this.onCompanyChanging,
    this.onCompanyChanged,
    this.brandingService,
    super.key,
  });

  final SyncStatusRepository statusRepository;
  final VoidCallback onLogout;
  final SyncCoordinator? coordinator;
  final ActiveCompanyContext? activeCompanyContext;
  final AuthRepository? authRepository;
  final VoidCallback? onCompanyChanging;
  final Future<void> Function()? onCompanyChanged;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: activeCompanyContext == null
            ? const Text('Secretary Dashboard')
            : CompanyBrandMark(
                context: activeCompanyContext!,
                service: brandingService,
                logoSize: 32,
                nameStyle: Theme.of(context).textTheme.titleSmall,
              ),
        actions: activeCompanyContext == null || authRepository == null
            ? null
            : [
                CompanySwitcher(
                  authRepository: authRepository!,
                  activeCompanyContext: activeCompanyContext!,
                  onCompanyChanging: onCompanyChanging,
                  onCompanyChanged: onCompanyChanged,
                ),
              ],
      ),
      drawer: _SecretaryDrawer(onLogout: onLogout),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Receiving desk',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Quick access to today\'s receiving work.'),
          const SizedBox(height: 24),
          SyncStatusCard(
            statusRepository: statusRepository,
            coordinator: coordinator,
          ),
          const SizedBox(height: 24),
          _ActionTile(
            icon: Icons.add_box_outlined,
            title: 'New Receiving',
            subtitle: 'Record a supplier delivery and bag weights.',
            route: AppRoutes.newReceiving,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.today_outlined,
            title: "Today's Records",
            subtitle: 'Review receiving records for the current day.',
            route: AppRoutes.todaysRecords,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Icon(
          icon,
          size: 32,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}

class _SecretaryDrawer extends StatelessWidget {
  const _SecretaryDrawer({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 20, 16),
          child: Text('Secretary App'),
        ),
        ListTile(
          leading: const Icon(Icons.dashboard_outlined),
          title: const Text('Dashboard'),
          onTap: () => Navigator.pop(context),
        ),
        ListTile(
          leading: const Icon(Icons.add_box_outlined),
          title: const Text('New Receiving'),
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.newReceiving);
          },
        ),
        ListTile(
          leading: const Icon(Icons.today_outlined),
          title: const Text("Today's Records"),
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, AppRoutes.todaysRecords);
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Log out'),
          onTap: () {
            onLogout();
            Navigator.pushReplacementNamed(context, AppRoutes.login);
          },
        ),
      ],
    );
  }
}
