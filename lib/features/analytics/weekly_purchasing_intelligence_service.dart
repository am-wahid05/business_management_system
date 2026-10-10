import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'analytics_models.dart';
import 'analytics_repository.dart';

typedef PythonProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  required String stdinText,
  String? workingDirectory,
  Map<String, String>? environment,
});

class WeeklyPurchasingIntelligenceService {
  WeeklyPurchasingIntelligenceService({
    required AnalyticsRepository analyticsRepository,
    String? pythonExecutable,
    String? pythonScriptPath,
    PythonProcessRunner? processRunner,
  }) : _analyticsRepository = analyticsRepository,
       _runtimePaths = WeeklyPurchasingPythonPaths.resolve(
         pythonExecutableOverride: pythonExecutable,
         pythonScriptOverride: pythonScriptPath,
       ),
       _processRunner = processRunner ?? _defaultPythonProcessRunner,
       _hasCustomProcessRunner = processRunner != null;

  final AnalyticsRepository _analyticsRepository;
  final WeeklyPurchasingPythonPaths _runtimePaths;
  final PythonProcessRunner _processRunner;
  final bool _hasCustomProcessRunner;

  String? get pythonExecutable => _runtimePaths.executable;
  String? get pythonScriptPath => _runtimePaths.script;

  bool get isRuntimeConfigured =>
      _runtimePaths.isConfigured &&
      (_hasCustomProcessRunner ||
          (File(_runtimePaths.executable!).existsSync() &&
              File(_runtimePaths.script!).existsSync()));

  Future<Map<String, dynamic>> buildWeeklySnapshot({
    required DateTime endDate,
    int weeks = 12,
  }) async {
    if (weeks <= 0) {
      throw ArgumentError.value(weeks, 'weeks', 'must be at least 1');
    }

    final weekStart = _startOfWeek(endDate);
    final snapshotWeeks = <Map<String, dynamic>>[];

    for (var weekOffset = 0; weekOffset < weeks; weekOffset++) {
      final start = weekStart.subtract(
        Duration(days: 7 * (weeks - 1 - weekOffset)),
      );
      final end = start.add(const Duration(days: 6));
      final results = await _analyticsRepository.productBreakdown(
        AnalyticsFilters(from: start, to: end),
      );

      final products = <String, double>{};
      for (final row in results) {
        final weight = row.totalWeight.isFinite ? row.totalWeight : 0.0;
        products[row.productId] = weight;
      }

      snapshotWeeks.add({'week_start': _isoDate(start), 'products': products});
    }

    return {'schema_version': 1, 'weeks': snapshotWeeks};
  }

  Future<Map<String, dynamic>> analyzeWeeklyPurchasing({
    required DateTime endDate,
    int weeks = 12,
  }) async {
    if (!isRuntimeConfigured) {
      throw StateError(
        _runtimePaths.isConfigured
            ? 'Configured Python runtime or script is unavailable.'
            : 'Python runtime is not configured.',
      );
    }

    final snapshot = await buildWeeklySnapshot(endDate: endDate, weeks: weeks);
    final jsonText = jsonEncode(snapshot);
    final executable = _runtimePaths.executable!;
    final scriptPath = _runtimePaths.script!;

    try {
      final result = await _processRunner(
        executable,
        ['-I', '-S', scriptPath],
        stdinText: jsonText,
      );

      if (result.exitCode != 0) {
        throw ProcessException(
          executable,
          [scriptPath],
          (result.stderr as String).isEmpty
              ? 'Python exited with code ${result.exitCode}.'
              : result.stderr.toString(),
          result.exitCode,
        );
      }

      final output = result.stdout.toString();
      if (output.trim().isEmpty) {
        throw const FormatException('Python returned no output.');
      }

      final decoded = jsonDecode(output);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Python returned malformed JSON output.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } on ProcessException {
      rethrow;
    } on FileSystemException {
      throw ProcessException(
        executable,
        [scriptPath],
        'Python runtime is unavailable at $executable.',
        127,
      );
    }
  }

  static Future<ProcessResult> _defaultPythonProcessRunner(
    String executable,
    List<String> arguments, {
    required String stdinText,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    process.stdin.add(utf8.encode(stdinText));
    await process.stdin.close();

    final stdout = await process.stdout.transform(utf8.decoder).join();
    final stderr = await process.stderr.transform(utf8.decoder).join();
    final exitCode = await process.exitCode;

    return ProcessResult(process.pid, exitCode, stdout, stderr);
  }

  static DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    );
  }

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class WeeklyPurchasingPythonPaths {
  const WeeklyPurchasingPythonPaths({this.executable, this.script});

  final String? executable;
  final String? script;

  bool get isConfigured =>
      (executable ?? '').trim().isNotEmpty && (script ?? '').trim().isNotEmpty;

  static WeeklyPurchasingPythonPaths resolve({
    String? pythonExecutableOverride,
    String? pythonScriptOverride,
    bool? isWindows,
    String? applicationExecutablePath,
  }) {
    final windows = isWindows ?? Platform.isWindows;
    final executablePath =
        applicationExecutablePath ?? Platform.resolvedExecutable;
    final runtimeDirectory = windows
        ? p.join(p.dirname(executablePath), 'python')
        : null;

    String? choose(String? override, String? bundledName) {
      if (override != null) {
        return override.trim().isEmpty ? null : override;
      }
      if (runtimeDirectory == null || bundledName == null) return null;
      return p.join(runtimeDirectory, bundledName);
    }

    return WeeklyPurchasingPythonPaths(
      executable: choose(pythonExecutableOverride, 'python.exe'),
      script: choose(pythonScriptOverride, 'weekly_purchasing_intelligence.py'),
    );
  }
}
