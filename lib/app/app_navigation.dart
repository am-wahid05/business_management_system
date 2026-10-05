import 'package:flutter/material.dart';

import '../features/auth/active_company_context.dart';
import '../features/auth/auth_models.dart';
import '../features/company/company_branding.dart';
import 'app_responsive.dart';
import 'app_routes.dart';
import 'app_theme.dart';

// -----------------------------------------------------------------------------
// Navigation destinations
// -----------------------------------------------------------------------------

/// One entry in the application navigation.
///
/// Declared once here so the persistent sidebar, the narrow-window drawer and
/// any future navigation control can never drift apart or point a label at a
/// different screen. [routes] lists every route that should light this entry
/// up, which is how a family of related screens (the three reports, for
/// example) shares a single active highlight.
@immutable
class AppNavDestination {
  const AppNavDestination({
    required this.label,
    required this.icon,
    required this.routes,
  });

  final String label;
  final IconData icon;

  /// The routes that select this destination. The first entry is the one the
  /// control navigates to.
  final List<String> routes;

  String get route => routes.first;

  /// Whether [current] should highlight this destination.
  bool matches(String? current) => current != null && routes.contains(current);
}

/// A titled group of [AppNavDestination]s in the sidebar and drawer.
@immutable
class AppNavSection {
  const AppNavSection({required this.title, required this.destinations});

  final String title;
  final List<AppNavDestination> destinations;
}

/// Every Admin destination, in the order the sidebar shows them.
///
/// This is the single source of truth for Admin navigation. Nothing is
/// invented: each entry points at a route that already exists in [AppRoutes]
/// and is already registered in the route table.
abstract final class AdminNav {
  static const dashboard = AppNavDestination(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    routes: [AppRoutes.adminDashboard],
  );

  static const suppliers = AppNavDestination(
    label: 'Suppliers',
    icon: Icons.people_outline,
    routes: [AppRoutes.suppliers],
  );

  static const products = AppNavDestination(
    label: 'Products',
    icon: Icons.inventory_2_outlined,
    routes: [AppRoutes.products],
  );

  static const reports = AppNavDestination(
    label: 'Reports',
    icon: Icons.assessment_outlined,
    routes: [
      AppRoutes.reports,
      AppRoutes.monthlyReports,
      AppRoutes.yearlyReports,
    ],
  );

  static const analytics = AppNavDestination(
    label: 'Analytics',
    icon: Icons.insights_outlined,
    routes: [AppRoutes.analytics],
  );

  static const statements = AppNavDestination(
    label: 'Statements',
    icon: Icons.receipt_long_outlined,
    routes: [AppRoutes.statements],
  );

  static const spreadsheet = AppNavDestination(
    label: 'Spreadsheet',
    icon: Icons.grid_on_outlined,
    // Excel is a destination in its own right, so it is deliberately not
    // listed here: sharing a route list would light up the Spreadsheet entry
    // while the Excel screen is open.
    routes: [AppRoutes.spreadsheet, AppRoutes.workbookGrid],
  );

  /// Exporting business records to a local .xlsx file.
  ///
  /// Reconnected to the Admin navigation: the screen, the service and the route
  /// all already existed, but no destination pointed at them, so the feature was
  /// only reachable by typing its route. Distinct from [spreadsheet], which is
  /// the on-screen editable grid, and from `excelImport`, which reads historical
  /// files back in.
  static const excel = AppNavDestination(
    label: 'Excel',
    icon: Icons.table_view_outlined,
    routes: [AppRoutes.excel],
  );

  static const assistant = AppNavDestination(
    label: 'Business Assistant',
    icon: Icons.auto_awesome_outlined,
    routes: [AppRoutes.assistant],
  );

  static const billing = AppNavDestination(
    label: 'Billing & SMS',
    icon: Icons.payments_outlined,
    routes: [AppRoutes.billing, AppRoutes.secretarySmsCredits],
  );

  static const users = AppNavDestination(
    label: 'Users',
    icon: Icons.manage_accounts_outlined,
    routes: [AppRoutes.users],
  );

  static const settings = AppNavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    routes: [AppRoutes.settings, AppRoutes.accountSettings],
  );

  static const about = AppNavDestination(
    label: 'About',
    icon: Icons.info_outline,
    routes: [AppRoutes.about, AppRoutes.aboutScreen],
  );

  static const sections = <AppNavSection>[
    AppNavSection(
      title: 'Workspace',
      destinations: [dashboard, suppliers, products],
    ),
    AppNavSection(
      title: 'Insight',
      destinations: [reports, analytics, statements],
    ),
    AppNavSection(
      title: 'Tools',
      destinations: [spreadsheet, excel, assistant],
    ),
    AppNavSection(
      title: 'Company',
      destinations: [billing, users, settings, about],
    ),
  ];
}

/// Every Secretary destination, shared by the rail, the navigation bar and the
/// compact drawer so a touch device gets the same set of places.
abstract final class SecretaryNav {
  static const dashboard = AppNavDestination(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    routes: [AppRoutes.secretaryDashboard],
  );

  static const receiving = AppNavDestination(
    label: 'Receiving',
    icon: Icons.add_box_outlined,
    routes: [AppRoutes.newReceiving],
  );

  static const todaysRecords = AppNavDestination(
    label: "Today's Records",
    icon: Icons.today_outlined,
    // Deliberately only the Secretary route. This destination used to also list
    // [AppRoutes.deliveries] so the Admin copy of the same screen lit this entry
    // up, but Today's Records is a Secretary workflow item and the Admin
    // navigation no longer offers it. Keeping the Admin route here would both
    // hand a Secretary an unreachable Admin destination and reintroduce the very
    // overlap the two navigation lists are kept apart to prevent.
    routes: [AppRoutes.todaysRecords],
  );

  static const printRecords = AppNavDestination(
    label: 'Print',
    icon: Icons.print_outlined,
    routes: [AppRoutes.secretaryPrintRecords],
  );

  static const smsCredits = AppNavDestination(
    label: 'SMS Credits',
    icon: Icons.sms_outlined,
    routes: [AppRoutes.secretarySmsCredits],
  );

  /// The Secretary's own account settings.
  ///
  /// This is the account-level screen, not the Admin company-settings screen:
  /// changing your own password grants no company-management permission, so it
  /// is reachable by a Secretary without exposing any Admin-only feature.
  static const settings = AppNavDestination(
    label: 'Settings',
    icon: Icons.settings_outlined,
    routes: [AppRoutes.accountSettings],
  );

  /// Read-only information about the software itself.
  ///
  /// Deliberately [AppRoutes.aboutScreen] and not the Admin-scoped
  /// [AppRoutes.about]: the About page is identical for every company and every
  /// role, so a Secretary is pointed at the shared route rather than a
  /// duplicate Secretary-specific implementation.
  static const about = AppNavDestination(
    label: 'About',
    icon: Icons.info_outline,
    routes: [AppRoutes.aboutScreen],
  );

  /// The primary Secretary destinations, shared by the rail, the navigation bar
  /// and the compact drawer.
  ///
  /// Only the workflow screens live here. The secondary destinations (Settings,
  /// About and the sign-out action) are listed separately in
  /// [secondaryDestinations] so they can be presented in a footer instead of
  /// competing with the primary tabs for space in the navigation bar.
  static const destinations = <AppNavDestination>[
    dashboard,
    receiving,
    todaysRecords,
    printRecords,
    smsCredits,
  ];

  /// Secondary Secretary destinations.
  ///
  /// These are shared with the primary set in meaning but presented separately
  /// so the narrow navigation bar keeps its five workflow tabs and the rail and
  /// drawer still offer these. [about] reuses the existing [AppRoutes.aboutScreen]
  /// route, so no second About implementation was created.
  static const secondaryDestinations = <AppNavDestination>[settings, about];
}

// -----------------------------------------------------------------------------
// Shell scope
// -----------------------------------------------------------------------------

/// Everything a screen needs to build its own navigation, published by the
/// shell that owns it.
///
/// Screens keep their own [Scaffold] so they keep control of their own AppBar,
/// body and FABs. Rather than making every screen reconstruct a drawer, the
/// shell publishes the already-correct one here and screens attach it with
/// [adminDrawerFor] / [secretaryDrawerFor].
///
/// The scope also records whether a persistent sidebar is already on screen, so
/// a screen can suppress the duplicate AppBar hamburger on wide layouts and
/// keep it on narrow ones.
class AppShellScope extends InheritedWidget {
  const AppShellScope({
    required this.role,
    required this.persistentSidebar,
    this.drawer,
    required super.child,
    super.key,
  });

  /// Which shell published this scope.
  final UserRole role;

  /// True when a persistent sidebar is part of the layout.
  ///
  /// When true, the attached drawer is suppressed so the user is never given
  /// two controls that do the same thing.
  final bool persistentSidebar;

  /// The drawer for this role, or null when the shell has nothing to offer.
  final Widget? drawer;

  static AppShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellScope>();

  /// True when a persistent sidebar is already on screen.
  ///
  /// This single bit is what stops a second hamburger appearing next to the
  /// real navigation.
  static bool hasPersistentSidebar(BuildContext context) =>
      of(context)?.persistentSidebar ?? false;

  @override
  bool updateShouldNotify(AppShellScope oldWidget) =>
      role != oldWidget.role ||
      persistentSidebar != oldWidget.persistentSidebar ||
      drawer != oldWidget.drawer;
}

/// The drawer an Admin screen should attach to its own [Scaffold].
///
/// Returns null when the persistent sidebar is already visible, which is how
/// the duplicate hamburger is avoided on desktop without every screen having
/// to measure the window itself.
Widget? adminDrawerFor(
  BuildContext context, {
  VoidCallback? onLogout,
  ActiveCompanyContext? activeCompanyContext,
  CompanyBrandingService? brandingService,
}) {
  final scope = AppShellScope.of(context);
  if (scope != null) {
    if (scope.role != UserRole.admin) return null;
    if (scope.persistentSidebar) return null;
    return scope.drawer;
  }
  // Outside a shell (a pushed detail screen, a test harness) fall back to a
  // standalone drawer so navigation is still reachable rather than absent.
  // Sign-out is a no-op when the caller has no session callback, rather than
  // deadlocking on a null.
  return AdminNavigationDrawer(
    onLogout: onLogout ?? () {},
    activeCompanyContext: activeCompanyContext,
    brandingService: brandingService,
  );
}

/// The drawer a Secretary screen should attach to its own [Scaffold].
///
/// Same contract as [adminDrawerFor]: null when the rail or the navigation bar
/// already provides navigation.
Widget? secretaryDrawerFor(
  BuildContext context, {
  VoidCallback? onLogout,
  ActiveCompanyContext? activeCompanyContext,
  CompanyBrandingService? brandingService,
}) {
  final scope = AppShellScope.of(context);
  if (scope != null) {
    if (scope.role != UserRole.secretary) return null;
    if (scope.persistentSidebar) return null;
    return scope.drawer;
  }
  return SecretaryNavigationDrawer(
    onLogout: onLogout ?? () {},
    activeCompanyContext: activeCompanyContext,
    brandingService: brandingService,
  );
}

/// The drawer that is correct for whichever role the shell is running as.
///
/// For a screen a Secretary and an Admin can both reach (About, Settings, a
/// supplier profile). Returns null when a persistent sidebar is already on
/// screen, matching [adminDrawerFor] / [secretaryDrawerFor].
Widget? shellDrawerFor(BuildContext context) {
  final scope = AppShellScope.of(context);
  if (scope == null || scope.persistentSidebar) return null;
  return scope.drawer;
}

// -----------------------------------------------------------------------------
// Admin shell
// -----------------------------------------------------------------------------

/// Shared desktop application shell for the Admin workspace.
///
/// Wide windows get a persistent, collapsible sidebar. Narrow windows keep the
/// screen's own drawer, so a small window never loses usable content width and
/// navigation is never lost.
class AdminShell extends StatefulWidget {
  const AdminShell({
    required this.child,
    required this.onLogout,
    this.activeCompanyContext,
    this.brandingService,
    super.key,
  });

  final Widget child;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final drawer = AdminNavigationDrawer(
      onLogout: widget.onLogout,
      activeCompanyContext: widget.activeCompanyContext,
      brandingService: widget.brandingService,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final persistent = constraints.maxWidth >= AppBreakpoints.sidebar;
        if (!persistent) {
          return AppShellScope(
            role: UserRole.admin,
            persistentSidebar: false,
            drawer: drawer,
            child: widget.child,
          );
        }
        return AppShellScope(
          role: UserRole.admin,
          persistentSidebar: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AdminSidebar(
                collapsed: _collapsed,
                onToggle: () => setState(() => _collapsed = !_collapsed),
                onLogout: widget.onLogout,
                activeCompanyContext: widget.activeCompanyContext,
                brandingService: widget.brandingService,
              ),
              const VerticalDivider(width: 1),
              Expanded(child: widget.child),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Sidebar
// -----------------------------------------------------------------------------

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.collapsed,
    required this.onToggle,
    required this.onLogout,
    this.activeCompanyContext,
    this.brandingService,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  /// Wide enough for the longest label ("Today's Receivings") at the app's body
  /// text size without truncating.
  static const double _expandedWidth = 268;

  /// An icon column with a comfortable touch target.
  static const double _collapsedWidth = 76;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: collapsed ? _collapsedWidth : _expandedWidth,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SidebarHeader(
              collapsed: collapsed,
              onToggle: onToggle,
              activeCompanyContext: activeCompanyContext,
              brandingService: brandingService,
            ),
            // The list scrolls so the sidebar can grow with its navigation
            // without ever pushing the account footer off screen.
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  collapsed ? 10 : 14,
                  6,
                  collapsed ? 10 : 14,
                  12,
                ),
                children: [
                  for (final section in AdminNav.sections) ...[
                    _SidebarSectionLabel(
                      label: section.title,
                      collapsed: collapsed,
                    ),
                    for (final destination in section.destinations)
                      _SidebarTile(
                        destination: destination,
                        collapsed: collapsed,
                      ),
                  ],
                ],
              ),
            ),
            _SidebarFooter(
              collapsed: collapsed,
              onLogout: onLogout,
              activeCompanyContext: activeCompanyContext,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggle,
    this.activeCompanyContext,
    this.brandingService,
  });

  final bool collapsed;
  final VoidCallback onToggle;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      padding: EdgeInsets.only(left: collapsed ? 16 : 18, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: collapsed
                ? const _BrandGlyph()
                : _CompanyIdentity(
                    activeCompanyContext: activeCompanyContext,
                    brandingService: brandingService,
                  ),
          ),
          IconButton(
            tooltip: collapsed ? 'Expand navigation' : 'Collapse navigation',
            onPressed: onToggle,
            icon: Icon(
              collapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandGlyph extends StatelessWidget {
  const _BrandGlyph();

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppTheme.primary,
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(Icons.grass_outlined, color: Colors.white, size: 22),
  );
}

class _CompanyIdentity extends StatelessWidget {
  const _CompanyIdentity({this.activeCompanyContext, this.brandingService});

  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    final active = activeCompanyContext;
    if (active == null) {
      return Row(
        children: [
          const _BrandGlyph(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  'Agricultural raw products',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return CompanyBrandMark(
      context: active,
      service: brandingService,
      logoSize: 38,
      nameStyle: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label, required this.collapsed});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    // A collapsed rail has no room for a word, so the label becomes a short
    // divider instead of being clipped to an unreadable stub.
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
        child: Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({required this.destination, required this.collapsed});

  final AppNavDestination destination;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    final selected = destination.matches(route);

    if (collapsed) {
      return Tooltip(
        message: destination.label,
        waitDuration: const Duration(milliseconds: 400),
        child: _CollapsedIconTile(
          destination: destination,
          selected: selected,
          onTap: () {
            if (selected) return;
            Navigator.of(context).pushReplacementNamed(destination.route);
          },
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return _SelectableTile(
      selected: selected,
      onTap: () {
        if (selected) return;
        Navigator.of(context).pushReplacementNamed(destination.route);
      },
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              destination.icon,
              size: 19,
              color: selected ? Colors.white : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedIconTile extends StatelessWidget {
  const _CollapsedIconTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 44,
            child: Icon(
              destination.icon,
              size: 21,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile with a deliberate hover state and a short active transition.
///
/// The shared behaviour lives here so the sidebar and the drawer cannot drift
/// apart in how they look or respond to the pointer.
class _SelectableTile extends StatefulWidget {
  const _SelectableTile({
    required this.selected,
    required this.onTap,
    required this.child,
    required this.borderRadius,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<_SelectableTile> createState() => _SelectableTileState();
}

class _SelectableTileState extends State<_SelectableTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = widget.selected
        ? scheme.primaryContainer
        : _hovered
        ? scheme.onSurface.withValues(alpha: 0.045)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: widget.borderRadius,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (value) => setState(() => _hovered = value),
          borderRadius: widget.borderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: background,
              borderRadius: widget.borderRadius,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.onLogout,
    this.activeCompanyContext,
  });

  final bool collapsed;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = activeCompanyContext?.value;

    final identity = user == null
        ? null
        : Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.primary,
                  child: Text(
                    _initials(user.displayName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        user.role == UserRole.admin
                            ? 'Administrator'
                            : 'Secretary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    void signOut() {
      onLogout();
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        collapsed ? 10 : 14,
        12,
        collapsed ? 10 : 14,
        14,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!collapsed && identity != null) ...[
            identity,
            const SizedBox(height: 8),
          ],
          if (collapsed)
            Tooltip(
              message: 'Sign out',
              waitDuration: const Duration(milliseconds: 400),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: signOut,
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    height: 44,
                    child: Icon(Icons.logout, size: 21, color: scheme.error),
                  ),
                ),
              ),
            )
          else
            _SelectableTile(
              selected: false,
              onTap: signOut,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.logout, size: 19, color: scheme.error),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sign out',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// -----------------------------------------------------------------------------
// Narrow-window drawers
// -----------------------------------------------------------------------------

/// One navigation row shared by both drawers.
///
/// Rendered from an [AppNavDestination] so a drawer row and a sidebar row can
/// never show different labels, icons or highlighting for the same screen.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SelectableTile(
      selected: selected,
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Icon(
            destination.icon,
            size: 21,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The drawer header shared by both drawers: identity plus a close control.
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.activeCompanyContext,
    required this.brandingService,
  });

  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: 18, right: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: activeCompanyContext == null
                ? const _BrandGlyph()
                : CompanyBrandMark(
                    context: activeCompanyContext!,
                    service: brandingService,
                    logoSize: 38,
                    nameStyle: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
          ),
          IconButton(
            tooltip: 'Close navigation',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// The sign-out row shared by both drawers.
class _DrawerSignOut extends StatelessWidget {
  const _DrawerSignOut({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: _SelectableTile(
        selected: false,
        onTap: () {
          onLogout();
          Navigator.of(context).pushReplacementNamed(AppRoutes.login);
        },
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Icon(Icons.logout, size: 21, color: scheme.error),
            const SizedBox(width: 14),
            Text(
              'Sign out',
              style: TextStyle(fontSize: 14.5, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Admin navigation drawer used below the sidebar breakpoint.
///
/// It renders exactly the destinations the sidebar renders, from the same
/// [AdminNav] list, so a narrow window can never be missing a place the wide
/// window offers.
class AdminNavigationDrawer extends StatelessWidget {
  const AdminNavigationDrawer({
    super.key,
    required this.onLogout,
    this.activeCompanyContext,
    this.brandingService,
  });

  final VoidCallback onLogout;

  /// Same active-company branding source used by the dashboard AppBar, so the
  /// drawer shows the active company's name/logo without any extra
  /// company-selection state.
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(
              activeCompanyContext: activeCompanyContext,
              brandingService: brandingService,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                children: [
                  for (final section in AdminNav.sections) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                      child: Text(
                        section.title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final destination in section.destinations)
                      _DrawerRow(
                        destination: destination,
                        selected: destination.matches(route),
                        onTap: () {
                          final navigator = Navigator.of(context);
                          navigator.pop();
                          navigator.pushReplacementNamed(destination.route);
                        },
                      ),
                  ],
                ],
              ),
            ),
            _DrawerSignOut(onLogout: onLogout),
          ],
        ),
      ),
    );
  }
}

/// The Secretary navigation drawer used on narrow windows, where the bottom
/// navigation bar cannot reach the secondary destinations.
class SecretaryNavigationDrawer extends StatelessWidget {
  const SecretaryNavigationDrawer({
    super.key,
    required this.onLogout,
    this.activeCompanyContext,
    this.brandingService,
  });

  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    final scheme = Theme.of(context).colorScheme;
    return Drawer(
      width: 300,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(
              activeCompanyContext: activeCompanyContext,
              brandingService: brandingService,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                children: [
                  for (final destination in SecretaryNav.destinations)
                    _DrawerRow(
                      destination: destination,
                      selected: destination.matches(route),
                      onTap: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        navigator.pushReplacementNamed(destination.route);
                      },
                    ),
                  const SizedBox(height: 18),
                  Divider(height: 1, color: scheme.outlineVariant),
                  const SizedBox(height: 10),
                  // Driven by SecretaryNav.secondaryDestinations so the drawer,
                  // the rail and the navigation bar cannot drift apart. Change
                  // password and About are reached through the shared
                  // accountSettings and aboutScreen routes.
                  for (final destination in SecretaryNav.secondaryDestinations)
                    _DrawerRow(
                      destination: destination,
                      selected: destination.matches(route),
                      onTap: () {
                        final navigator = Navigator.of(context);
                        navigator.pop();
                        navigator.pushReplacementNamed(destination.route);
                      },
                    ),
                ],
              ),
            ),
            _DrawerSignOut(onLogout: onLogout),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Secretary shell
// -----------------------------------------------------------------------------

/// Touch-first navigation shell for Secretary workflows.
///
/// A tablet or desktop window gets a rail. A phone-sized window gets a bottom
/// navigation bar, which is the correct control for a thumb. Both are built
/// from [SecretaryNav.destinations], so the two layouts offer the same places.
class SecretaryShell extends StatefulWidget {
  const SecretaryShell({
    required this.child,
    required this.onLogout,
    this.activeCompanyContext,
    this.brandingService,
    super.key,
  });

  final Widget child;
  final VoidCallback onLogout;
  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;

  @override
  State<SecretaryShell> createState() => _SecretaryShellState();
}

class _SecretaryShellState extends State<SecretaryShell> {
  @override
  Widget build(BuildContext context) {
    final drawer = SecretaryNavigationDrawer(
      onLogout: widget.onLogout,
      activeCompanyContext: widget.activeCompanyContext,
      brandingService: widget.brandingService,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final persistent = constraints.maxWidth >= AppBreakpoints.sidebar;
        if (persistent) {
          return AppShellScope(
            role: UserRole.secretary,
            persistentSidebar: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SecretaryRail(
                  activeCompanyContext: widget.activeCompanyContext,
                  brandingService: widget.brandingService,
                  onLogout: widget.onLogout,
                ),
                const VerticalDivider(width: 1),
                Expanded(child: widget.child),
              ],
            ),
          );
        }
        return AppShellScope(
          role: UserRole.secretary,
          persistentSidebar: false,
          drawer: drawer,
          child: Scaffold(
            body: widget.child,
            bottomNavigationBar: const _SecretaryNavigationBar(),
          ),
        );
      },
    );
  }
}

class _SecretaryRail extends StatelessWidget {
  const _SecretaryRail({
    this.activeCompanyContext,
    this.brandingService,
    required this.onLogout,
  });

  final ActiveCompanyContext? activeCompanyContext;
  final CompanyBrandingService? brandingService;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final route = ModalRoute.of(context)?.settings.name;
    final selected = SecretaryNav.destinations.indexWhere(
      (destination) => destination.matches(route),
    );
    return Container(
      width: 96,
      color: scheme.surface,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            Container(
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: activeCompanyContext == null
                  ? const _BrandGlyph()
                  : CompanyBrandMark(
                      context: activeCompanyContext!,
                      service: brandingService,
                      logoSize: 38,
                      // The rail shows only icons, so the name is collapsed to a
                      // hairline rather than allowed to wrap into the tile.
                      nameStyle: const TextStyle(fontSize: 1, height: 0.1),
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  for (
                    var index = 0;
                    index < SecretaryNav.destinations.length;
                    index++
                  )
                    _RailTile(
                      destination: SecretaryNav.destinations[index],
                      selected: selected == index,
                    ),
                ],
              ),
            ),
            // The rail replaces the drawer on wide layouts, so the secondary
            // destinations and the sign-out action have to be reachable here
            // too. Without this footer a Secretary on a tablet or desktop would
            // have no visible way to reach About, change their password or sign
            // out at all.
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final destination in SecretaryNav.secondaryDestinations)
                    _RailActionTile(
                      destination: destination,
                      onTap: () =>
                          Navigator.of(context)
                              .pushReplacementNamed(destination.route),
                    ),
                  _RailSignOut(onLogout: onLogout),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({required this.destination, required this.selected});

  final AppNavDestination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
        child: Material(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              if (selected) return;
              Navigator.of(context).pushReplacementNamed(destination.route);
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    destination.icon,
                    size: 22,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      destination.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.15,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact icon-only tile for a secondary destination in the Secretary rail.
///
/// Mirrors [_RailTile] but carries no selected state, because the secondary
/// destinations are reached as a separate screen rather than as one of the
/// rail's primary tabs. The label is still rendered so the control is readable
/// without hovering, matching the primary tiles.
class _RailActionTile extends StatelessWidget {
  const _RailActionTile({required this.destination, required this.onTap});

  final AppNavDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: destination.label,
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    destination.icon,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      destination.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Secretary rail's sign-out control.
///
/// This calls the same [onLogout] callback the Admin sidebar and both drawers
/// use, so there is exactly one logout implementation in the application and the
/// session is cleared by the same code path for every role.
class _RailSignOut extends StatelessWidget {
  const _RailSignOut({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Sign out',
      waitDuration: const Duration(milliseconds: 400),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            // Signing out has to return the user to the Sign In screen, not
            // merely clear the session. Without the navigation the Secretary
            // would be left sitting on a dashboard whose user no longer exists:
            // the session is gone but the screen is still there, so it reads as
            // a half-finished sign-in rather than a completed sign-out. This is
            // the same two-step the Admin sidebar footer and both drawers
            // already perform, so every role now ends a sign-out identically.
            onTap: () {
              onLogout();
              Navigator.of(context).pushReplacementNamed(AppRoutes.login);
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.logout, size: 20, color: scheme.error),
                  const SizedBox(height: 4),
                  Text(
                    'Sign out',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w500,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecretaryNavigationBar extends StatelessWidget {
  const _SecretaryNavigationBar();

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)?.settings.name;
    var selected = SecretaryNav.destinations.indexWhere(
      (destination) => destination.matches(route),
    );
    // A detail screen pushed on top of a Secretary destination still shows the
    // bar, so fall back to the first destination rather than leaving the
    // selection pointing at nothing.
    if (selected < 0) selected = 0;
    return NavigationBar(
      height: 68,
      selectedIndex: selected,
      onDestinationSelected: (index) {
        final destination = SecretaryNav.destinations[index];
        if (destination.matches(route)) return;
        Navigator.of(context).pushReplacementNamed(destination.route);
      },
      destinations: SecretaryNav.destinations
          .map(
            (destination) => NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.icon),
              // Five destinations will not fit as full words on a narrow phone,
              // so the longest label is shortened rather than truncated.
              label: destination == SecretaryNav.todaysRecords
                  ? 'Today'
                  : destination.label,
            ),
          )
          .toList(growable: false),
    );
  }
}
