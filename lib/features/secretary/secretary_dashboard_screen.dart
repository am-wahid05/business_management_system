import 'package:flutter/material.dart';

import '../../app/app_routes.dart';
import '../../app/app_navigation.dart';
import '../../app/app_ui.dart';
import '../../domain/models/delivery.dart';
import '../auth/active_company_context.dart';
import '../auth/auth_repository.dart';
import '../company/company_branding.dart';
import '../credits/sms_credit_service.dart';
import '../receiving/delivery_repository.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_status_card.dart';
import '../sync/sync_status_repository.dart';

class SecretaryDashboardScreen extends StatelessWidget {
  const SecretaryDashboardScreen({
    required this.deliveryRepository,
    required this.statusRepository,
    required this.onLogout,
    this.coordinator,
    this.activeCompanyContext,
    this.authRepository,
    this.brandingService,
    this.creditService,
    this.onCompanyChanging,
    this.onCompanyChanged,
    super.key,
  });

  final DeliveryRepository deliveryRepository;
  final SyncStatusRepository statusRepository;
  final VoidCallback onLogout;
  final SyncCoordinator? coordinator;
  final ActiveCompanyContext? activeCompanyContext;
  final AuthRepository? authRepository;
  final CompanyBrandingService? brandingService;
  final SmsCreditService? creditService;
  final VoidCallback? onCompanyChanging;
  final Future<void> Function()? onCompanyChanged;

  @override
  Widget build(BuildContext context) {
    final user = authRepository?.currentUser;
    final companyName = activeCompanyContext?.companyName ?? 'Company';
    return Scaffold(
      appBar: AppBar(
        title: activeCompanyContext == null
            ? const Text('Secretary Dashboard')
            : CompanyBrandMark(
                context: activeCompanyContext!,
                service: brandingService,
              ),
        actions: [
          if (authRepository != null && activeCompanyContext != null)
            CompanySwitcher(
              authRepository: authRepository!,
              activeCompanyContext: activeCompanyContext!,
              onCompanyChanging: onCompanyChanging,
              onCompanyChanged: onCompanyChanged,
            ),
        ],
      ),
      drawer: secretaryDrawerFor(context, onLogout: onLogout),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SecretaryWelcomeCard(
            companyName: companyName,
            userName: user?.displayName ?? 'Secretary',
            syncEnabled: coordinator != null,
          ),
          const SizedBox(height: 24),
          _TodaySummary(repository: deliveryRepository),
          const SizedBox(height: 24),
          Text('Quick actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 3 : 1;
              final width =
                  (constraints.maxWidth - ((columns - 1) * 12)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _ActionTile(
                      icon: Icons.add_box_outlined,
                      title: 'New Receiving',
                      subtitle: 'Record a supplier delivery and bag weights.',
                      route: AppRoutes.newReceiving,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _ActionTile(
                      icon: Icons.today_outlined,
                      title: "Today's Receivings",
                      subtitle: 'Review today\'s saved receiving history.',
                      route: AppRoutes.todaysRecords,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _ActionTile(
                      icon: Icons.print_outlined,
                      title: 'Print Records',
                      subtitle: 'Select saved receipts and open print preview.',
                      route: AppRoutes.secretaryPrintRecords,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _ActionTile(
                      icon: Icons.sms_outlined,
                      title: 'SMS Credits',
                      subtitle:
                          'View the company balance and your permissions.',
                      route: AppRoutes.secretarySmsCredits,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          SyncStatusCard(
            statusRepository: statusRepository,
            coordinator: coordinator,
          ),
        ],
      ),
    );
  }
}

class _SecretaryWelcomeCard extends StatelessWidget {
  const _SecretaryWelcomeCard({
    required this.companyName,
    required this.userName,
    required this.syncEnabled,
  });

  final String companyName;
  final String userName;
  final bool syncEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              companyName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Secretary workspace Â· $userName',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  syncEnabled
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  syncEnabled
                      ? 'Sync enabled Â· records remain available offline'
                      : 'Offline mode Â· records remain stored on this device',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.86),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  const _TodaySummary({required this.repository});

  final DeliveryRepository repository;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return FutureBuilder<List<Delivery>>(
      future: repository.forDate(today),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeleton(width: 170, height: 22),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: AppKpiSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AppKpiSkeleton()),
                  SizedBox(width: 12),
                  Expanded(child: AppKpiSkeleton()),
                ],
              ),
            ],
          );
        }
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Today\'s receiving summary is temporarily unavailable.',
              ),
            ),
          );
        }
        final records = snapshot.data ?? const <Delivery>[];
        final bags = records.fold<int>(
          0,
          (total, item) => total + item.numberOfBags,
        );
        final weight = records.fold<double>(
          0,
          (total, item) => total + item.totalWeight,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today at a glance',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 900 ? 3 : 1;
                final width =
                    (constraints.maxWidth - ((columns - 1) * 12)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _SummaryMetric(
                        icon: Icons.receipt_long_outlined,
                        label: 'Today\'s receivings',
                        value: '${records.length}',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryMetric(
                        icon: Icons.scale_outlined,
                        label: 'Total weight',
                        value: '${weight.toStringAsFixed(1)} kg',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryMetric(
                        icon: Icons.inventory_2_outlined,
                        label: 'Total bags',
                        value: '$bags',
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: theme.textTheme.headlineSmall),
                ],
              ),
            ),
          ],
        ),
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
