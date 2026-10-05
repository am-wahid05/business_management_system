import 'package:flutter/material.dart';

import '../auth/change_password_screen.dart';
import 'account_service.dart';

/// Account settings that every signed-in user can reach.
///
/// This screen deliberately contains no company or user-management controls.
/// Its only action is changing the signed-in user's OWN password, which is an
/// account-security action rather than a company-management one, so it must not
/// be hidden behind admin permissions. The screen cannot change anybody else's
/// password: [ChangePasswordScreen] only ever updates the credential of the
/// current authenticated session, and it requires the current password to be
/// re-entered before anything is written.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({required this.accountService, super.key});

  final AccountService? accountService;

  @override
  Widget build(BuildContext context) {
    final service = accountService;
    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Your account',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            service?.currentEmail == null
                ? 'These settings apply to your own signed-in account only.'
                : 'These settings apply to ${service!.currentEmail} only.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          if (service == null || !service.isAvailable)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Password changes are not available in this installation.',
                ),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change Password'),
                subtitle: const Text(
                  'Update your own account password. You will be asked for your '
                  'current password first.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ChangePasswordScreen(accountService: service),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Your company role comes from your company membership and cannot be '
            'changed here. Ask a company owner or admin if your role is wrong.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
