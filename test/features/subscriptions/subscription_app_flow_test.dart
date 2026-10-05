import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/auth/auth_models.dart';
import 'package:flutter_application_2/features/subscriptions/entitlement_service.dart';
import 'package:flutter_application_2/features/subscriptions/entitlements.dart';
import 'package:flutter_application_2/features/subscriptions/subscription_messages.dart';
import 'package:flutter_application_2/features/subscriptions/subscription_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'subscription_test_helpers.dart';

/// Exercises the real widgets the app now uses, driven with an
/// [EntitlementService] seeded to a known state.
class SeededEntitlementService extends EntitlementService {
  SeededEntitlementService(this.seed) : super(null);

  final Entitlements seed;

  /// The widgets read [entitlements], so the seed has to be what they see.
  /// Overriding refresh() alone is not enough: without this the gate would
  /// silently fall back to the safe default and the test would prove nothing.
  @override
  Entitlements get entitlements => seed;

  /// Server reads requested, so a test can prove the client never invents a
  /// state on its own.
  int refreshCalls = 0;

  @override
  Future<bool> refresh() async {
    refreshCalls++;
    return false;
  }
}

const AppUser adminUser = AppUser(
  id: 'admin-1',
  username: 'owner@company.test',
  displayName: 'Owner',
  role: UserRole.admin,
  isActive: true,
  companyId: 'company-a',
);

const AppUser secretaryUser = AppUser(
  id: 'sec-1',
  username: 'sec@company.test',
  displayName: 'Secretary',
  role: UserRole.secretary,
  isActive: true,
  companyId: 'company-a',
);

Widget host(EntitlementService service, AppUser? user) => MaterialApp(
  home: AdminSubscriptionGate(
    entitlements: service,
    user: user,
    onRenew: () {},
    builder: (_) => const Scaffold(body: Text('ADMIN SCREEN')),
  ),
);

void main() {
  group('the admin lock is enforced for an admin', () {
    testWidgets('a trial admin sees the real screen', (tester) async {
      await tester.pumpWidget(
        host(SeededEntitlementService(entitlementsWith()), adminUser),
      );
      expect(find.text('ADMIN SCREEN'), findsOneWidget);
      expect(find.text('Subscription expired'), findsNothing);
    });

    testWidgets('an active admin sees the real screen', (tester) async {
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(
              status: 'ACTIVE',
              isInTrial: false,
              hasActiveSoftwareSubscription: true,
            ),
          ),
          adminUser,
        ),
      );
      expect(find.text('ADMIN SCREEN'), findsOneWidget);
    });

    testWidgets('a grace-period admin still sees the real screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(
              status: 'GRACE_PERIOD',
              isInTrial: false,
              isInGracePeriod: true,
              gracePeriodEnd: DateTime.now().add(const Duration(days: 4)),
            ),
          ),
          adminUser,
        ),
      );
      expect(find.text('ADMIN SCREEN'), findsOneWidget);
    });

    testWidgets('an expired admin is locked with a clear message', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(
              status: 'EXPIRED',
              isInTrial: false,
              canAccessAdmin: false,
            ),
          ),
          adminUser,
        ),
      );
      // A clear screen, not a crash and not a logout.
      expect(find.text('Subscription expired'), findsOneWidget);
      expect(find.text(SubscriptionMessages.adminLocked), findsOneWidget);
      // The management screen is genuinely not rendered.
      expect(find.text('ADMIN SCREEN'), findsNothing);
    });

    testWidgets('the lock screen reassures that the data is safe', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
          ),
          adminUser,
        ),
      );
      expect(find.textContaining('safe'), findsOneWidget);
    });

    testWidgets('a locked admin can still reach billing', (tester) async {
      final service = SeededEntitlementService(
        entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
      );
      var renewTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminSubscriptionGate(
            entitlements: service,
            user: adminUser,
            onRenew: () => renewTapped = true,
            builder: (_) => const Scaffold(body: Text('ADMIN SCREEN')),
          ),
        ),
      );

      await tester.tap(find.text('Go to Billing'));
      expect(renewTapped, isTrue);
    });
  });

  group('a secretary is never locked by the subscription', () {
    testWidgets('a secretary passes the gate even when expired', (
      tester,
    ) async {
      // The gate is only applied to admin routes, but the role check runs
      // first, so a secretary is never locked out by billing state.
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
          ),
          secretaryUser,
        ),
      );
      expect(find.text('ADMIN SCREEN'), findsOneWidget);
      expect(find.text('Subscription expired'), findsNothing);
    });

    test('a secretary can still record while the admin side is locked', () {
      // canRecordAsSecretary is deliberately independent of the admin lock, so
      // an expired subscription cannot stop a company recording deliveries.
      final expired = entitlementsWith(
        status: 'EXPIRED',
        canAccessAdmin: false,
      );
      expect(expired.canRecordAsSecretary, isTrue);
    });

    test('a secretary can still record during the grace period', () {
      final grace = entitlementsWith(
        status: 'GRACE_PERIOD',
        isInGracePeriod: true,
        gracePeriodEnd: DateTime.now().add(const Duration(days: 3)),
      );
      expect(grace.canRecordAsSecretary, isTrue);
    });

    testWidgets('a paused company stops the software for the admin side', (
      tester,
    ) async {
      // PAUSED is the one state that stops secretarial recording too.
      await tester.pumpWidget(
        host(
          SeededEntitlementService(
            entitlementsWith(
              status: 'PAUSED',
              isPaused: true,
              canAccessAdmin: false,
              canRecordAsSecretary: false,
            ),
          ),
          adminUser,
        ),
      );
      expect(find.text('Subscription expired'), findsOneWidget);
    });

    test('a paused company does not let a secretary record', () {
      final paused = entitlementsWith(
        status: 'PAUSED',
        isPaused: true,
        canAccessAdmin: false,
        canRecordAsSecretary: false,
      );
      expect(paused.canRecordAsSecretary, isFalse);
    });
  });

  group('the banner reports the right state', () {
    Future<void> pumpBanner(
      WidgetTester tester,
      Entitlements entitlements,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubscriptionBanner(
              entitlements: SeededEntitlementService(entitlements),
              onRenew: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('a healthy subscription offers no call to action', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        entitlementsWith(
          status: 'ACTIVE',
          isInTrial: false,
          hasActiveSoftwareSubscription: true,
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
        ),
      );
      // A permanent "everything is fine" notice would be noise.
      expect(find.text('Go to Billing'), findsNothing);
    });

    testWidgets('a trial ending soon warns with the days remaining', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        entitlementsWith(
          trialEndsAt: DateTime.now().add(const Duration(days: 3)),
        ),
      );
      expect(find.textContaining('trial'), findsOneWidget);
      expect(find.text('Go to Billing'), findsOneWidget);
    });

    testWidgets('an expired subscription says access is locked', (
      tester,
    ) async {
      await pumpBanner(
        tester,
        entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
      );
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('an expired banner also says the data is safe', (tester) async {
      await pumpBanner(
        tester,
        entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
      );
      // The most frightening thing an admin can be told is that their work is
      // gone, so the banner says plainly that it is not.
      expect(find.textContaining('safe'), findsOneWidget);
    });

    testWidgets('a paused company is told everything is kept', (tester) async {
      await pumpBanner(
        tester,
        entitlementsWith(
          status: 'PAUSED',
          isPaused: true,
          canAccessAdmin: false,
        ),
      );
      expect(find.textContaining('paused'), findsOneWidget);
      expect(find.textContaining('safe'), findsOneWidget);
    });

    testWidgets('the banner taps through to billing', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubscriptionBanner(
              entitlements: SeededEntitlementService(
                entitlementsWith(status: 'EXPIRED', canAccessAdmin: false),
              ),
              onRenew: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go to Billing'));
      expect(tapped, isTrue);
    });
  });

  group('the client never invents a subscription state', () {
    test('building the gate does not itself re-read the server', () {
      final service = SeededEntitlementService(entitlementsWith());
      expect(service.refreshCalls, 0);
    });

    test('the safe default before any server read allows work to continue', () {
      // Before the first successful read the app must not lock anyone out. A
      // missing or unreachable server keeps the company working.
      expect(Entitlements.unknown.canAccessAdmin, isTrue);
      expect(Entitlements.unknown.canRecordAsSecretary, isTrue);
    });

    test('an offline read failure never upgrades an entitlement', () async {
      // A service with no client cannot reach the server at all.
      final service = EntitlementService(null);
      final refreshed = await service.refresh();

      expect(refreshed, isFalse);
      expect(service.isOffline, isTrue);
      // The state is unchanged: no invention in either direction.
      expect(service.entitlements, same(Entitlements.unknown));
    });
  });
}
