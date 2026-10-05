import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../receiving/paper_size.dart';
import '../receiving/print_settings_service.dart';

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_responsive.dart';
import '../../app/app_ui.dart';
import '../backup/backup_service.dart';
import '../auth/active_company_context.dart';
import '../auth/account_service.dart';
import '../auth/auth_models.dart';
import '../auth/change_password_screen.dart';
import '../company/company_branding.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.backupService,
    this.accountService,
    this.brandingService,
    this.activeCompanyContext,
    super.key,
  });

  final BackupService backupService;
  final AccountService? accountService;
  final CompanyBrandingService? brandingService;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _working = false;
  String? _message;
  _SettingsCategory? _selected;

  /// The categories with real content for the signed-in user.
  ///
  /// Account needs a backend-backed account service, and company branding is
  /// admin-only, so a category the user cannot use is not shown at all rather
  /// than rendered as a dead link.
  ///
  /// Printing is offered to everyone, because a Secretary prints the receipts
  /// far more often than an Admin does. Paper sizes are a company preference and
  /// are saved by whoever can administer the company; in the local
  /// single-company setup there is no company row, so the values are simply
  /// remembered on this device.
  List<_SettingsCategory> get _categories {
    return [
      if (widget.accountService?.isAvailable ?? false)
        _SettingsCategory.account,
      if (widget.brandingService != null &&
          widget.activeCompanyContext?.value?.role == UserRole.admin)
        _SettingsCategory.company,
      _SettingsCategory.printing,
      _SettingsCategory.backups,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final selected = (_selected != null && categories.contains(_selected))
        ? _selected!
        : categories.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: adminDrawerFor(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // A wide window gives the categories their own column so the content
          // stays scannable. A narrow window stacks every section instead,
          // which keeps the buttons reachable.
          if (constraints.maxWidth < AppBreakpoints.medium) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final category in categories) ...[
                  AppSectionHeader(
                    title: category.label,
                    subtitle: category.description,
                  ),
                  const SizedBox(height: 14),
                  _sectionBody(context, category),
                  const SizedBox(height: 28),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: _SettingsNavigation(
                  categories: categories,
                  selected: selected,
                  onSelected: (category) =>
                      setState(() => _selected = category),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    AppSectionHeader(
                      title: selected.label,
                      subtitle: selected.description,
                    ),
                    const SizedBox(height: 14),
                    _sectionBody(context, selected),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionBody(BuildContext context, _SettingsCategory category) {
    switch (category) {
      case _SettingsCategory.printing:
        return _PrintingSettingsSection(
          client: widget.brandingService?.client,
          activeCompanyContext: widget.activeCompanyContext,
        );
      case _SettingsCategory.account:
        return Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change Password'),
            subtitle: const Text('Update your account password.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChangePasswordScreen(
                  accountService: widget.accountService!,
                ),
              ),
            ),
          ),
        );
      case _SettingsCategory.company:
        return _CompanyBrandingSettings(
          service: widget.brandingService!,
          activeCompanyContext: widget.activeCompanyContext!,
        );
      case _SettingsCategory.backups:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Backups contain business records only. Login passwords and password secrets are never included.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            // Wrapped rather than left in a fixed-height row, so the two
            // buttons stack on a narrow window instead of overflowing a Row.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _working ? null : _createBackup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Create Backup'),
                ),
                OutlinedButton.icon(
                  onPressed: _working ? null : _restoreBackup,
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore Backup'),
                ),
              ],
            ),
            if (_working) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 20),
              SelectableText(_message!),
            ],
            const SizedBox(height: 16),
            const AppPanel(
              child: Text(
                'Cloud synchronization provides another layer of protection by uploading synchronized delivery records to Supabase. Keep both local backups and cloud synchronization enabled where possible.',
              ),
            ),
          ],
        );
    }
  }

  Future<void> _createBackup() async {
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final file = await widget.backupService.createBackup();
      if (mounted) setState(() => _message = 'Backup created: ${file.path}');
    } catch (error) {
      if (mounted) setState(() => _message = 'Backup failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'Restoring can replace current local business data. A safety backup of the current data will be created first. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final selectedPath = selection?.files.single.path;
    if (selectedPath == null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final safetyBackup = await widget.backupService.restoreBackup(
        File(selectedPath),
      );
      if (mounted) {
        setState(
          () => _message =
              'Restore complete. Safety backup: ${safetyBackup.path}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Restore failed: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _CompanyBrandingSettings extends StatefulWidget {
  const _CompanyBrandingSettings({
    required this.service,
    required this.activeCompanyContext,
  });

  final CompanyBrandingService service;
  final ActiveCompanyContext activeCompanyContext;

  @override
  State<_CompanyBrandingSettings> createState() =>
      _CompanyBrandingSettingsState();
}

class _CompanyBrandingSettingsState extends State<_CompanyBrandingSettings> {
  late final TextEditingController _nameController;
  late final TextEditingController _senderIdController;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.activeCompanyContext.companyName ?? '',
    );
    _senderIdController = TextEditingController(
      text: widget.activeCompanyContext.value?.companySmsSenderId ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _senderIdController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    await _run(
      () => widget.service.updateCompanyName(_nameController.text),
      'Company name saved.',
    );
  }

  Future<void> _saveSenderId() async {
    await _run(
      () => widget.service.updateSmsSenderId(_senderIdController.text),
      'SMS sender ID saved. Receipts will now be sent using this sender ID.',
    );
  }

  Future<void> _chooseLogo() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      withData: true,
    );
    final selectedFiles = selection?.files;
    if (selectedFiles == null || selectedFiles.isEmpty) return;
    final bytes = selectedFiles.first.bytes;
    if (bytes == null) {
      if (selection != null && mounted) {
        _showMessage('Could not read the selected PNG image.');
      }
      return;
    }
    await _run(
      () => widget.service.uploadLogo(bytes),
      'Company logo uploaded.',
    );
  }

  Future<void> _removeLogo() async {
    await _run(widget.service.removeLogo, 'Company logo removed.');
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _working = true);
    try {
      await action();
      if (mounted) _showMessage(success);
    } catch (error) {
      if (mounted) _showMessage('Could not update company branding: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ValueListenableBuilder<AppUser?>(
          valueListenable: widget.activeCompanyContext,
          builder: (context, user, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Company branding',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                enabled: !_working,
                decoration: const InputDecoration(labelText: 'Company name'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: CompanyLogo(
                  path: user?.companyLogoPath,
                  size: 72,
                  service: widget.service,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _working ? null : _saveName,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save name'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _working ? null : _chooseLogo,
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Upload or replace logo'),
                  ),
                  if (user?.companyLogoPath != null)
                    TextButton.icon(
                      onPressed: _working ? null : _removeLogo,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove logo'),
                    ),
                ],
              ),
              if (_working)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 8),
              Text(
                'Choose a PNG image up to 5 MB. Only company owners and admins can change branding.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Divider(height: 32),
              Text(
                'SMS sender ID',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Receipts sent by SMS use this sender ID. It must already be registered and approved in Sailup for this company. Secretaries cannot change it, and each company can only send using its own.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _senderIdController,
                enabled: !_working,
                decoration: InputDecoration(
                  labelText: 'Approved Sailup sender ID',
                  helperText: 'Leave empty if SMS is not used. Up to 11 letters or digits, or up to 15 digits.',
                  errorText: (() {
                    final value = _senderIdController.text.trim();
                    if (value.isEmpty || isValidSmsSenderId(value)) {
                      return null;
                    }
                    return 'Use up to 11 letters or digits, or up to 15 digits.';
                  })(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _working ? null : _saveSenderId,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save sender ID'),
                ),
              ),
              if (user?.companySmsSenderId == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No sender ID is configured yet. Until one is set and approved in Sailup, sending a receipt by SMS will report a configuration error.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings → Printing.
///
/// Paper sizes are a company preference, so they are read from and written to
/// the active company. When there is no company (the local single-company
/// setup) the same values are remembered on this device, so the screen is
/// still useful rather than being a dead form.
class _PrintingSettingsSection extends StatefulWidget {
  const _PrintingSettingsSection({
    required this.client,
    required this.activeCompanyContext,
  });

  final SupabaseClient? client;
  final ActiveCompanyContext? activeCompanyContext;

  @override
  State<_PrintingSettingsSection> createState() =>
      _PrintingSettingsSectionState();
}

class _PrintingSettingsSectionState extends State<_PrintingSettingsSection> {
  CompanyPrintProfile? _profile;
  List<Printer> _printers = const [];
  bool _canListPrinters = false;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await PrintPreferences.current(
      client: widget.client,
      context: widget.activeCompanyContext,
    );
    // Printer enumeration is a platform capability, not an assumption. If the
    // running platform cannot list printers, no printer list is shown at all
    // rather than an empty box that looks broken.
    var printers = <Printer>[];
    var canList = false;
    try {
      final info = await Printing.info();
      canList = info.canListPrinters;
      if (canList) printers = await Printing.listPrinters();
    } catch (_) {
      canList = false;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _printers = printers;
      _canListPrinters = canList;
    });
  }

  Future<void> _update(CompanyPrintProfile next) async {
    setState(() {
      _profile = next;
      _saving = true;
      _message = null;
    });
    final companyId = widget.activeCompanyContext?.value?.companyId;
    try {
      if (companyId != null && widget.client != null) {
        await CompanyPrintProfileService(
          widget.client!,
          widget.activeCompanyContext!,
        ).save(next);
      }
      PrintPreferences.remember(companyId, next);
      if (mounted) setState(() => _message = 'Printing settings saved.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      return const AppSkeleton(width: 260, height: 160);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader(
          title: 'Printing',
          subtitle:
              'Paper sizes and the print preview for the active company. '
              'These settings belong to this company only.',
        ),
        const SizedBox(height: 18),
        _paperField(
          context,
          label: 'Receipt paper size',
          helper:
              'Thermal rolls print a narrow receipt layout; sheets print a '
              'full page.',
          value: profile.receiptPaper,
          options: PaperSize.receiptOptions,
          onChanged: (size) => _update(profile.copyWith(receiptPaper: size)),
        ),
        const SizedBox(height: 18),
        _paperField(
          context,
          label: 'Report paper size',
          helper: 'Used for reports and analytics.',
          value: profile.reportPaper,
          options: PaperSize.sheetOptions,
          onChanged: (size) => _update(profile.copyWith(reportPaper: size)),
        ),
        const SizedBox(height: 18),
        _paperField(
          context,
          label: 'Supplier statement paper size',
          helper: 'Used for supplier histories and statements.',
          value: profile.statementPaper,
          options: PaperSize.sheetOptions,
          onChanged: (size) => _update(profile.copyWith(statementPaper: size)),
        ),
        const SizedBox(height: 18),
        SwitchListTile.adaptive(
          value: profile.showPreview,
          onChanged: (value) => _update(profile.copyWith(showPreview: value)),
          title: const Text('Show print preview'),
          subtitle: const Text(
            'Show the document before sending it to the printer.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 18),
        _printerSection(context),
        if (_saving) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_message != null) ...[
          const SizedBox(height: 12),
          Text(_message!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  Widget _paperField(
    BuildContext context, {
    required String label,
    required String helper,
    required PaperSize value,
    required List<PaperSize> options,
    required ValueChanged<PaperSize> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        DropdownButtonFormField<PaperSize>(
          initialValue: value,
          items: [
            for (final size in options)
              DropdownMenuItem(value: size, child: Text(size.label)),
          ],
          onChanged: (size) {
            if (size != null) onChanged(size);
          },
        ),
        const SizedBox(height: 4),
        Text(helper, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  /// The printer list, only when the platform can actually provide one.
  ///
  /// Printing goes through the operating system's own print dialog, so this is
  /// a convenience rather than a requirement. Where enumeration is not
  /// supported the section says so plainly instead of showing an empty picker
  /// that cannot work.
  Widget _printerSection(BuildContext context) {
    if (!_canListPrinters) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This device does not support choosing a printer here. '
                  'Printing still uses the default printer from the system '
                  'print dialog.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available printers',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Printing uses the system print dialog. A printer belongs to this '
          'computer rather than to the company, so it is never shared between '
          'companies.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final printer in _printers)
              Chip(
                avatar: Icon(
                  printer.isDefault
                      ? Icons.check_circle_outline
                      : Icons.print_outlined,
                  size: 16,
                ),
                label: Text(printer.name),
              ),
          ],
        ),
      ],
    );
  }
}

/// The settings sections that actually exist in this application.
///
/// Only real, working sections appear here; there is deliberately no entry for
/// something the app does not support yet.
enum _SettingsCategory {
  account(
    'Account',
    'Your sign-in credentials for this account.',
    Icons.lock_outline,
  ),
  company(
    'Company',
    'Company name, logo, and the SMS sender ID used on receipts.',
    Icons.business_outlined,
  ),
  printing(
    'Printing',
    'Paper sizes, printers and the print preview for this company.',
    Icons.print_outlined,
  ),
  backups(
    'Backups & data',
    'Local backups and cloud synchronization for business records.',
    Icons.backup_outlined,
  );

  const _SettingsCategory(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// The category list shown beside the settings content on wide windows.
class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<_SettingsCategory> categories;
  final _SettingsCategory selected;
  final ValueChanged<_SettingsCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              selected: category == selected,
              selectedTileColor: scheme.primary.withValues(alpha: 0.10),
              selectedColor: scheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(category.icon),
              title: Text(
                category.label,
                style: TextStyle(
                  fontWeight: category == selected
                      ? FontWeight.w700
                      : FontWeight.w600,
                ),
              ),
              onTap: () => onSelected(category),
            ),
          ),
      ],
    );
  }
}
