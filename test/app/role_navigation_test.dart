import 'package:flutter_application_2/app/app_navigation.dart';
import 'package:flutter_application_2/app/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The destination with [label] somewhere in [sections].
///
/// Reads a single entry by name so a test can compare two destinations without
/// repeating the double loop, and fails loudly if the label disappears.
AppNavDestination _destination(List<AppNavSection> sections, String label) {
  for (final section in sections) {
    for (final destination in section.destinations) {
      if (destination.label == label) return destination;
    }
  }
  throw StateError('No destination labelled "$label" exists.');
}

/// Locks in the role split between the two navigation surfaces.
///
/// These assertions read the same [AdminNav] / [SecretaryNav] lists that the
/// sidebar, the rail, the bottom bar and both drawers render from, so a
/// destination cannot quietly reappear in one role's navigation without a test
/// failing here.
void main() {
  List<String> adminLabels() => [
    for (final section in AdminNav.sections)
      for (final destination in section.destinations) destination.label,
  ];

  List<String> adminRoutes() => [
    for (final section in AdminNav.sections)
      for (final destination in section.destinations) ...destination.routes,
  ];

  group('Admin navigation', () {
    test('does not offer the Secretary receiving workflow', () {
      final labels = adminLabels();
      expect(labels, isNot(contains('Receiving')));
      expect(labels, isNot(contains('New Receiving')));
      expect(labels, isNot(contains("Today's Records")));
      expect(labels, isNot(contains("Today's Receivings")));
    });

    test('does not link to any receiving route', () {
      final routes = adminRoutes();
      expect(routes, isNot(contains(AppRoutes.newReceiving)));
      expect(routes, isNot(contains(AppRoutes.todaysRecords)));
      expect(routes, isNot(contains(AppRoutes.deliveries)));
      expect(routes, isNot(contains(AppRoutes.adminReceiving)));
    });

    test('keeps the legitimate Admin destinations', () {
      final labels = adminLabels();
      for (final expected in [
        'Dashboard',
        'Suppliers',
        'Products',
        'Reports',
        'Analytics',
        'Spreadsheet',
        'Excel',
        'Business Assistant',
        'Billing & SMS',
        'Settings',
      ]) {
        expect(labels, contains(expected));
      }
    });

    test('offers Excel for exporting records', () {
      // The Excel screen, service and route already existed; only the
      // destination that reached them was missing. This guards it against
      // being dropped again.
      expect(adminLabels(), contains('Excel'));
      expect(adminRoutes(), contains(AppRoutes.excel));
    });

    test(
      'keeps Excel separate from Spreadsheet so it lights up on its own',
      () {
        final spreadsheet = _destination(AdminNav.sections, 'Spreadsheet');
        final excel = _destination(AdminNav.sections, 'Excel');

        expect(spreadsheet.routes, isNot(contains(AppRoutes.excel)));
        // Excel claims exactly its own route, so neither entry highlights while
        // the other's screen is open.
        expect(excel.routes, [AppRoutes.excel]);
      },
    );

    test('every Admin destination points at an absolute route', () {
      for (final section in AdminNav.sections) {
        for (final destination in section.destinations) {
          expect(
            destination.route,
            startsWith('/'),
            reason: '${destination.label} must use an absolute route',
          );
          expect(
            destination.routes,
            isNotEmpty,
            reason: '${destination.label} must highlight at least one route',
          );
        }
      }
    });
  });

  group('Secretary navigation', () {
    test('retains the receiving workflow and Today\'s Records', () {
      final labels = SecretaryNav.destinations.map((d) => d.label).toList();
      expect(labels, contains('Dashboard'));
      expect(labels, contains('Receiving'));
      expect(labels, contains("Today's Records"));
      expect(labels, contains('Print'));
      expect(labels, contains('SMS Credits'));
    });

    test('retains Settings and About as secondary destinations', () {
      final labels = SecretaryNav.secondaryDestinations
          .map((destination) => destination.label)
          .toList();
      expect(labels, contains('Settings'));
      expect(labels, contains('About'));
    });

    test('About reuses the shared About route rather than a duplicate', () {
      expect(SecretaryNav.about.route, AppRoutes.aboutScreen);
      expect(SecretaryNav.about.route, isNot(AppRoutes.about));
    });

    test('does not offer Excel, which is an Admin-only feature', () {
      final labels = [
        ...SecretaryNav.destinations,
        ...SecretaryNav.secondaryDestinations,
      ].map((destination) => destination.label).toList();
      final routes = [
        ...SecretaryNav.destinations,
        ...SecretaryNav.secondaryDestinations,
      ].expand((destination) => destination.routes);

      expect(labels, isNot(contains('Excel')));
      expect(routes, isNot(contains(AppRoutes.excel)));
    });

    test('the Secretary never links to an Admin-only route', () {
      final routes = [
        ...SecretaryNav.destinations,
        ...SecretaryNav.secondaryDestinations,
      ].expand((destination) => destination.routes);
      for (final route in routes) {
        expect(
          route,
          isNot(contains('/admin')),
          reason:
              '$route is an Admin route and must not appear for a Secretary',
        );
      }
    });
  });

  group('routes are preserved for both roles', () {
    test('the receiving routes still exist', () {
      // Only the navigation entries were split by role; the shared screens and
      // their routes are untouched, so both shells can still open them.
      expect(AppRoutes.newReceiving, '/secretary/new-receiving');
      expect(AppRoutes.todaysRecords, '/secretary/todays-records');
      expect(AppRoutes.deliveries, '/admin/deliveries');
      expect(AppRoutes.adminReceiving, '/admin/receiving');
    });

    test('the shared About and account settings routes still exist', () {
      expect(AppRoutes.aboutScreen, '/about');
      expect(AppRoutes.accountSettings, '/account/settings');
    });
  });

  group('destination matching', () {
    test('a destination lights up for every route in its family', () {
      expect(AdminNav.reports.matches(AppRoutes.reports), isTrue);
      expect(AdminNav.reports.matches(AppRoutes.monthlyReports), isTrue);
      expect(AdminNav.reports.matches(AppRoutes.yearlyReports), isTrue);
      expect(AdminNav.reports.matches(AppRoutes.products), isFalse);
    });

    test('an unknown route highlights nothing', () {
      expect(AdminNav.dashboard.matches(null), isFalse);
      expect(AdminNav.dashboard.matches('/nowhere'), isFalse);
    });
  });
}
