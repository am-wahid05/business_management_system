import 'package:flutter/material.dart';

import 'app_routes.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.subtitle,
    required this.icon,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: const _AppNavigationDrawer(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 20),
                    Text(title, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    const Chip(label: Text('Coming in a later phase')),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppNavigationDrawer extends StatelessWidget {
  const _AppNavigationDrawer();

  @override
  Widget build(BuildContext context) {
    return NavigationDrawer(
      header: const Padding(
        padding: EdgeInsets.fromLTRB(28, 24, 20, 16),
        child: Text('AL-BNC Ventures'),
      ),
      children: [
        _navigationDestination(context, 'Login', Icons.lock_outline, AppRoutes.login),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: Text('Secretary'),
        ),
        _navigationDestination(context, 'Secretary Dashboard', Icons.scale, AppRoutes.secretaryDashboard),
        _navigationDestination(context, 'New Receiving', Icons.add_box_outlined, AppRoutes.newReceiving),
        _navigationDestination(context, "Today's Records", Icons.today_outlined, AppRoutes.todaysRecords),
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 16, 16, 8),
          child: Text('Management'),
        ),
        _navigationDestination(context, 'Admin Dashboard', Icons.dashboard_outlined, AppRoutes.adminDashboard),
        _navigationDestination(context, 'Suppliers', Icons.people_outline, AppRoutes.suppliers),
        _navigationDestination(context, 'Reports', Icons.assessment_outlined, AppRoutes.reports),
        _navigationDestination(context, 'Settings', Icons.settings_outlined, AppRoutes.settings),
      ],
    );
  }

  Widget _navigationDestination(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        Navigator.pushReplacementNamed(context, route);
      },
    );
  }
}
