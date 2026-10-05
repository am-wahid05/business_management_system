import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/active_company_context.dart';
import 'paper_size.dart';

/// Reads and writes a company's printing preferences.
///
/// Two separate stores, deliberately not mixed:
///
/// * Company preferences (paper sizes, whether to preview) live in Supabase
///   against the `companies` row, so they follow the company to every machine
///   and are protected by the same company RLS as the company's name and logo.
///   Every read and write is scoped by `company_id`, so one company can never
///   see or change another's.
/// * Printer names are device settings and are never stored here. See
///   [DevicePrinterPreference].
class CompanyPrintProfileService {
  CompanyPrintProfileService(this.client, this.activeCompanyContext) {
    // Remember the client so any screen can ask for the active company's
    // settings without having to be handed the Supabase client itself. This
    // holds a connection, never a credential: the signed-in session still comes
    // from Supabase's own auth state, so this cannot be used to reach a company
    // the signed-in user is not a member of.
    PrintPreferences.attachClient(client);
    PrintPreferences.rememberContext(activeCompanyContext);
  }

  final SupabaseClient client;
  final ActiveCompanyContext activeCompanyContext;

  /// The company whose settings are being read or written.
  String? get _companyId {
    final user = activeCompanyContext.value;
    final id = user?.companyId;
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// Loads the active company's printing preferences.
  ///
  /// Returns defaults when there is no company (the local single-company setup),
  /// or when the row cannot be read. A printing preference must never be the
  /// reason a document fails to open, so a read failure degrades to defaults
  /// rather than throwing.
  Future<CompanyPrintProfile> load() async {
    final companyId = _companyId;
    if (companyId == null) return const CompanyPrintProfile();
    try {
      final row = await client
          .from('companies')
          .select(
            'receipt_paper_size, report_paper_size, '
            'statement_paper_size, print_show_preview',
          )
          .eq('id', companyId)
          .single();
      return CompanyPrintProfile.fromCompanyRow(row);
    } catch (_) {
      return const CompanyPrintProfile();
    }
  }

  /// Saves the active company's printing preferences.
  ///
  /// The update is filtered by the active `company_id`, and the database's own
  /// RLS re-checks that the signed-in user may update this company. Both are
  /// needed: the filter alone would happily write to a company the user cannot
  /// administer, and RLS alone is not an argument the caller chooses.
  Future<void> save(CompanyPrintProfile profile) async {
    final companyId = _companyId;
    if (companyId == null) {
      throw StateError('No active company to save printing settings to.');
    }
    await client
        .from('companies')
        .update(profile.toCompanyColumns())
        .eq('id', companyId);
  }
}

/// Resolves the printing preferences that apply right now.
///
/// Print actions happen in many screens, none of which should have to know how
/// settings are stored, so this is the one place that answers "what paper does
/// the active company print on".
///
/// Results are cached per company id, which is what makes switching companies
/// behave correctly: Company A's answer is returned for Company A and never
/// handed to Company B. A company that has never been loaded resolves to the
/// defaults, so a brand new company prints sensibly with no setup.
abstract final class PrintPreferences {
  static final Map<String, CompanyPrintProfile> _cache = {};
  static CompanyPrintProfile? localOverride;
  static SupabaseClient? _client;
  static ActiveCompanyContext? _lastContext;

  /// The connection used to read company settings, when one is available.
  static void attachClient(SupabaseClient? client) => _client = client;

  /// Remembers the most recently used company context.
  ///
  /// Print actions live in several screens and none of them should have to own
  /// a reference to the backend. Holding the context here means a print action
  /// can always ask which company is active, even when the screen hosting it has
  /// no client of its own. The context carries the signed-in user, so this is
  /// the same identity the rest of the app is already acting as.
  static void rememberContext(ActiveCompanyContext? context) =>
      _lastContext = context;

  /// The profile in force for the local single-company setup.
  ///
  /// Only ever set from the settings screen, and never read when a real company
  /// is active, so it cannot leak into another company.

  /// Loads the active company's profile.  ///
  /// [client] is optional; the attached client is used when it is omitted, so a
  /// print action anywhere in the app can simply ask. When neither is available
  /// the defaults are returned: printing must keep working in the local setup,
  /// where there is no backend at all.
  static Future<CompanyPrintProfile> current({
    SupabaseClient? client,
    required ActiveCompanyContext? context,
  }) async {
    final active = context ?? _lastContext;
    final companyId = active?.value?.companyId;
    if (companyId == null || companyId.isEmpty) {
      return localOverride ?? const CompanyPrintProfile();
    }
    final cached = _cache[companyId];
    if (cached != null) return cached;
    final supabase = client ?? _client;
    if (supabase == null || active == null) {
      return localOverride ?? const CompanyPrintProfile();
    }
    final profile = await CompanyPrintProfileService(supabase, active).load();
    _cache[companyId] = profile;
    return profile;
  }

  /// Stores a profile for a company after a successful save, so the next print
  /// uses the new value without waiting for another read.
  static void remember(String? companyId, CompanyPrintProfile profile) {
    if (companyId == null || companyId.isEmpty) {
      localOverride = profile;
      return;
    }
    _cache[companyId] = profile;
  }

  /// Drops every cached profile.
  ///
  /// Used when signing out, so the next user on this machine cannot read the
  /// previous user's company settings out of memory.
  static void clear() {
    _cache.clear();
    localOverride = null;
    _lastContext = null;
  }
}

/// Stores printer choices for the machine this app is running on.
///
/// A printer is a property of a device, not of a business, so this never talks
/// to Supabase and never travels between machines. The file is keyed by
/// company id, so two companies used on the same PC each keep their own printer
/// while neither is forced onto another computer.
class DevicePrintSettingsStore {
  DevicePrintSettingsStore({this.fileName = 'print_settings.json'});

  /// Overridable so tests can use a scratch file instead of the real one.
  final String fileName;

  File? _cache;

  Future<File> _file() async {
    if (_cache != null) return _cache!;
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    _cache = file;
    return file;
  }

  /// The printer preference for one company on this device.
  Future<DevicePrinterPreference> load(String? companyId) async {
    final all = await _loadAll();
    if (companyId == null) return const DevicePrinterPreference();
    final entry = all[companyId];
    if (entry is Map<String, dynamic>) {
      return DevicePrinterPreference.fromJson(entry);
    }
    return const DevicePrinterPreference();
  }

  /// Saves one company's printer choice, leaving every other company alone.
  Future<void> save(
    String? companyId,
    DevicePrinterPreference preference,
  ) async {
    if (companyId == null) return;
    final all = await _loadAll();
    all[companyId] = preference.toJson();
    await _writeAll(all);
  }

  Future<Map<String, dynamic>> _loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final text = await file.readAsString();
      if (text.trim().isEmpty) return {};
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      // A corrupt or unreadable settings file must not stop the app printing.
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> all) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(all));
  }
}
