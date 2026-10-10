import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_application_2/features/analytics/analytics_report_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains when Python is not configured', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WeeklyPurchasingInsightsSection(
            isRuntimeConfigured: false,
            loadInsights: _unusedLoader,
          ),
        ),
      ),
    );

    expect(find.textContaining('Python is not configured'), findsOneWidget);
    expect(find.text('Generate weekly insights'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('shows a loading state and renders Python insight values', (
    tester,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyPurchasingInsightsSection(
            isRuntimeConfigured: true,
            loadInsights: () => completer.future,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Generate weekly insights'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete({
      'schema_version': 1,
      'method': 'advisory',
      'weekly_totals': [
        {'week_start': '2026-09-21', 'total_weight': 60.0},
        {'week_start': '2026-09-28', 'total_weight': 290.0},
      ],
      'latest_week': {
        'week_start': '2026-09-28',
        'total_weight': 290.0,
        'week_over_week_percent': 383.3,
        'historical_mean': 60.0,
        'historical_median': 60.0,
        'unusual_volume': true,
        'unusual_volume_explanation':
            'Above the historical mean; advisory only.',
      },
      'products': [],
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Latest week: 2026-09-28'), findsOneWidget);
    expect(find.text('383.3%'), findsOneWidget);
    expect(find.text('60.0 kg'), findsNWidgets(3));
    expect(
      find.text('Above the historical mean; advisory only.'),
      findsOneWidget,
    );
    expect(find.text('2026-09-21'), findsOneWidget);
    expect(find.text('2026-09-28'), findsOneWidget);
  });

  testWidgets('shows an actionable error without affecting the screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyPurchasingInsightsSection(
            isRuntimeConfigured: true,
            loadInsights: () async => throw StateError('Python unavailable'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Generate weekly insights'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Python unavailable'), findsOneWidget);
    expect(find.text('Generate weekly insights'), findsOneWidget);
  });

  testWidgets('rejects unsupported Python output with a visible error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeeklyPurchasingInsightsSection(
            isRuntimeConfigured: true,
            loadInsights: () async => {'schema_version': 2},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Generate weekly insights'));
    await tester.pumpAndSettle();

    expect(find.textContaining('unsupported result'), findsOneWidget);
  });
}

Future<Map<String, dynamic>> _unusedLoader() async =>
    throw StateError('The loader must not run when Python is unconfigured.');
