import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      // The settings list is long, so it scrolls rather than trying to fit every
      // section on one screen. A small window or a phone therefore keeps the
      // buttons reachable instead of pushing them off the bottom.
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Business data backup',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Backups contain business records only. Login passwords and password secrets are never included.',
          ),
          const SizedBox(height: 20),
          // Wrapped rather than left in a fixed-height row, so the two buttons
          // stack on a narrow window instead of overflowing a Row.
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
          const SizedBox(height: 28),
          if (widget.accountService?.isAvailable ?? false) ...[
            Card(
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
            ),
            const SizedBox(height: 28),
          ],
          if (widget.brandingService != null &&
              widget.activeCompanyContext?.value?.role == UserRole.admin) ...[
            _CompanyBrandingSettings(
              service: widget.brandingService!,
              activeCompanyContext: widget.activeCompanyContext!,
            ),
            const SizedBox(height: 28),
          ],
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Cloud synchronization provides another layer of protection by uploading synchronized delivery records to Supabase. Keep both local backups and cloud synchronization enabled where possible.',
              ),
            ),
          ),
        ],
      ),
    );
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
                  helperText:
                      'Leave empty if SMS is not used. Up to 11 letters or digits, or up to 15 digits.',
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
