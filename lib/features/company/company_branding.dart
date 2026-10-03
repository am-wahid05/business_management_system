import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/active_company_context.dart';
import '../auth/auth_models.dart';
import '../auth/auth_repository.dart';

class CompanyBranding {
  const CompanyBranding({
    required this.companyId,
    required this.name,
    this.logoPath,
    this.smsSenderId,
  });

  final String companyId;
  final String name;
  final String? logoPath;

  /// The company's approved Sailup sender ID, or null when not configured.
  final String? smsSenderId;

  factory CompanyBranding.fromUser(AppUser user) => CompanyBranding(
    companyId: user.companyId ?? '',
    name: user.companyName ?? 'Company',
    logoPath: user.companyLogoPath,
    smsSenderId: user.companySmsSenderId,
  );
}

/// A Sailup sender ID is either a numeric MSISDN (max 15 digits) or an
/// alphanumeric ID of up to 11 characters. This mirrors the database check
/// constraint so an unusable value is rejected before it is saved.
bool isValidSmsSenderId(String value) {
  if (RegExp(r'^[0-9]{1,15}$').hasMatch(value)) return true;
  return RegExp(r'^[A-Za-z0-9 ]{3,11}$').hasMatch(value) &&
      value.trim() == value;
}

/// Supabase client operations for a company's own branding.
/// Company updates and Storage writes are authorized by database RLS.
class CompanyBrandingService {
  CompanyBrandingService(this.client, this.activeCompanyContext);

  static const bucket = 'company-logos';

  final SupabaseClient client;
  final ActiveCompanyContext activeCompanyContext;
  final Map<String, Future<String>> _signedUrlCache = {};
  final Map<String, DateTime> _signedUrlExpiry = {};

  CompanyBranding? get currentBranding {
    final user = activeCompanyContext.value;
    if (user == null || user.companyId == null) return null;
    return CompanyBranding.fromUser(user);
  }

  Future<CompanyBranding> load(String companyId) async {
    final row = await client
        .from('companies')
        .select('id, name, logo_path')
        .eq('id', companyId)
        .single();
    return CompanyBranding(
      companyId: row['id'] as String,
      name: row['name'] as String,
      logoPath: row['logo_path'] as String?,
    );
  }

  Future<String> signedLogoUrl(String path) async {
    final expiry = _signedUrlExpiry[path];
    final cached = _signedUrlCache[path];
    if (cached != null && expiry != null && DateTime.now().isBefore(expiry)) {
      return cached;
    }
    final request = client.storage.from(bucket).createSignedUrl(path, 60 * 60);
    _signedUrlCache[path] = request;
    _signedUrlExpiry[path] = DateTime.now().add(const Duration(minutes: 55));
    try {
      return await request;
    } catch (_) {
      _signedUrlCache.remove(path);
      _signedUrlExpiry.remove(path);
      rethrow;
    }
  }

  Future<Uint8List> downloadLogo(String path) =>
      client.storage.from(bucket).download(path);

  Future<void> updateCompanyName(String name) async {
    final companyId = _requireCompanyId();
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Company name is required.');
    await client
        .from('companies')
        .update({'name': cleanName})
        .eq('id', companyId);
    _updateActiveUser(companyName: cleanName);
  }

  Future<void> uploadLogo(Uint8List bytes) async {
    if (bytes.isEmpty) throw ArgumentError('Choose a PNG image with content.');
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Company logos must be 5 MB or smaller.');
    }
    final companyId = _requireCompanyId();
    final path = '$companyId/logo.png';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
            cacheControl: '0',
          ),
        );
    await client
        .from('companies')
        .update({'logo_path': path})
        .eq('id', companyId);
    _signedUrlCache.remove(path);
    _updateActiveUser(companyLogoPath: path);
  }

  Future<void> removeLogo() async {
    final companyId = _requireCompanyId();
    final path = activeCompanyContext.logoPath;
    await client
        .from('companies')
        .update({'logo_path': null})
        .eq('id', companyId);
    _updateActiveUser(clearLogoPath: true);
    if (path != null) {
      await client.storage.from(bucket).remove([path]);
      _signedUrlCache.remove(path);
      _signedUrlExpiry.remove(path);
    }
  }

  /// Reads the company's configured Sailup sender ID, or null when not set.
  Future<String?> loadSmsSenderId(String companyId) async {
    final row = await client
        .from('companies')
        .select('sms_sender_id')
        .eq('id', companyId)
        .single();
    final value = row['sms_sender_id'] as String?;
    return value != null && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// Saves the company's Sailup sender ID.
  ///
  /// The value must already be registered and approved in Sailup; this only
  /// records which approved ID belongs to this company. Only owners and admins
  /// can write it, enforced by the `companies_owner_admin_update` RLS policy.
  /// Passing an empty value clears the configuration.
  Future<void> updateSmsSenderId(String senderId) async {
    final companyId = _requireCompanyId();
    final clean = senderId.trim();
    if (clean.isNotEmpty && !isValidSmsSenderId(clean)) {
      throw ArgumentError(
        'A sender ID must be up to 11 letters or digits, or up to 15 digits.',
      );
    }
    await client
        .from('companies')
        .update({'sms_sender_id': clean.isEmpty ? null : clean})
        .eq('id', companyId);
    _updateActiveUser(
      companySmsSenderId: clean.isEmpty ? null : clean,
      clearCompanySmsSenderId: clean.isEmpty,
    );
  }

  String _requireCompanyId() {
    final companyId = activeCompanyContext.companyId;
    if (companyId == null) throw StateError('Sign in to a company first.');
    return companyId;
  }

  void _updateActiveUser({
    String? companyName,
    String? companyLogoPath,
    bool clearLogoPath = false,
    String? companySmsSenderId,
    bool clearCompanySmsSenderId = false,
  }) {
    final current = activeCompanyContext.value;
    if (current == null) return;
    activeCompanyContext.value = current.copyWith(
      companyName: companyName,
      companyLogoPath: companyLogoPath,
      clearCompanyLogoPath: clearLogoPath,
      companySmsSenderId: companySmsSenderId,
      clearCompanySmsSenderId: clearCompanySmsSenderId,
    );
  }
}

class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    required this.path,
    required this.size,
    this.service,
    super.key,
  });

  final String? path;
  final double size;
  final CompanyBrandingService? service;

  @override
  Widget build(BuildContext context) {
    final currentPath = path;
    final currentService = service;
    if (currentPath == null || currentPath.isEmpty || currentService == null) {
      return _placeholder(context);
    }
    return FutureBuilder<String>(
      future: currentService.signedLogoUrl(currentPath),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return _placeholder(context);
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            snapshot.data!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _placeholder(context),
          ),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(Icons.business_outlined, color: Colors.white, size: size * .58),
  );
}

class CompanyBrandMark extends StatelessWidget {
  const CompanyBrandMark({
    required this.context,
    this.service,
    this.logoSize = 42,
    this.nameStyle,
    super.key,
  });

  final ActiveCompanyContext context;
  final CompanyBrandingService? service;
  final double logoSize;
  final TextStyle? nameStyle;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUser?>(
      valueListenable: this.context,
      builder: (context, user, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompanyLogo(
            path: user?.companyLogoPath,
            size: logoSize,
            service: service,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              user?.companyName ?? 'Company Management',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  nameStyle ??
                  Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class CompanySwitcher extends StatelessWidget {
  const CompanySwitcher({
    required this.authRepository,
    required this.activeCompanyContext,
    this.onCompanyChanging,
    this.onCompanyChanged,
    super.key,
  });

  final AuthRepository authRepository;
  final ActiveCompanyContext activeCompanyContext;
  final VoidCallback? onCompanyChanging;
  final Future<void> Function()? onCompanyChanged;

  @override
  Widget build(BuildContext context) {
    if (!authRepository.isRemote) return const SizedBox.shrink();
    return FutureBuilder<List<CompanyMembership>>(
      future: authRepository.companiesForCurrentUser(),
      builder: (context, snapshot) {
        final memberships = snapshot.data;
        if (memberships == null || memberships.length < 2) {
          return const SizedBox.shrink();
        }
        return PopupMenuButton<String>(
          tooltip: 'Switch company',
          icon: const Icon(Icons.swap_horiz),
          onSelected: (companyId) async {
            try {
              onCompanyChanging?.call();
              await authRepository.selectCompany(companyId);
              await onCompanyChanged?.call();
            } catch (error) {
              try {
                await onCompanyChanged?.call();
              } catch (_) {}
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not switch company: $error')),
              );
            }
          },
          itemBuilder: (context) => memberships
              .map(
                (membership) => PopupMenuItem<String>(
                  value: membership.companyId,
                  child: Row(
                    children: [
                      Icon(
                        membership.companyId == activeCompanyContext.companyId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Flexible(child: Text(membership.companyName)),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}
