import 'package:flutter/material.dart';

import '../../app/app_ui.dart';
import '../auth/auth_models.dart';
import 'local_auth_repository.dart';

/// A field with its label set above the control rather than inside it.
///
/// The floating in-field label moves up and down as the user types, which on a
/// form this short reads as jitter. A fixed label above the field is stable and
/// matches the layout the rest of the application uses.
class AuthLabeledField extends StatelessWidget {
  const AuthLabeledField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}

/// The Administrator / Secretary choice, shown only for the local setup.
///
/// Rendered as a segmented control rather than two full-size buttons: it is a
/// small preference, not the primary action, and it must not compete with the
/// sign-in button underneath it.
class AuthRoleSelector extends StatelessWidget {
  const AuthRoleSelector({
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final UserRole selected;
  final bool enabled;
  final ValueChanged<UserRole> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign in as',
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(fontSize: 13.5),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: _RoleSegment(
                  icon: Icons.admin_panel_settings_outlined,
                  label: 'Administrator',
                  selected: selected == UserRole.admin,
                  enabled: enabled,
                  onTap: () => onSelected(UserRole.admin),
                ),
              ),
              Expanded(
                child: _RoleSegment(
                  icon: Icons.badge_outlined,
                  label: 'Secretary',
                  selected: selected == UserRole.secretary,
                  enabled: enabled,
                  onTap: () => onSelected(UserRole.secretary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleSegment extends StatelessWidget {
  const _RoleSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: selected ? scheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        elevation: selected ? 1 : 0,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The style for text that navigates somewhere else rather than acting on the
/// form it sits in.
///
/// These controls read as links precisely because of the underline: they leave
/// the current screen instead of submitting anything, and a plain Material
/// `TextButton` does not draw one. The size, weight and colour are inherited
/// from the theme's label-large so the underline matches the surrounding
/// typography instead of introducing a second style, and the colour is resolved
/// by the button's own states so hover, focus and disabled still work.
///
/// Shared rather than private so every link-style control in the authentication
/// flow carries the identical underline instead of each screen restating it and
/// letting the treatments drift apart.
ButtonStyle authLinkStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return TextButton.styleFrom(
    foregroundColor: scheme.primary,
    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
  );
}

/// The "forgot password" and "create account" row.
///
/// Both live under the primary action, which is where a user looks for them,
/// and each is only rendered when the service behind it actually exists.
class AuthLinks extends StatelessWidget {
  const AuthLinks({
    required this.showSignUp,
    required this.showForgotPassword,
    required this.onSignUp,
    required this.onForgotPassword,
    super.key,
  });

  final bool showSignUp;
  final bool showForgotPassword;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    if (!showSignUp && !showForgotPassword) {
      return Text(
        'Contact your company administrator if you cannot sign in.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 2,
      runSpacing: 0,
      children: [
        if (showForgotPassword)
          TextButton(
            onPressed: onForgotPassword,
            style: authLinkStyle(context),
            child: const Text('Forgot password?'),
          ),
        if (showSignUp)
          TextButton(
            onPressed: onSignUp,
            style: authLinkStyle(context),
            child: const Text('Create account'),
          ),
      ],
    );
  }
}

/// The seeded local accounts, shown as a small secondary panel.
///
/// Only rendered in the local setup, where these accounts are the real,
/// documented way in. It replaces a block of raw credential text printed
/// straight into the middle of the form.
class LocalAccountsHint extends StatelessWidget {
  const LocalAccountsHint({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget row(String role, String username, String password) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              role,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$username / $password',
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'Consolas',
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.key_outlined,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                'LOCAL TEST ACCOUNTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          row(
            'Admin',
            LocalAuthRepository.testUsername,
            LocalAuthRepository.testPassword,
          ),
          row(
            'Secretary',
            LocalAuthRepository.testSecretaryUsername,
            LocalAuthRepository.testSecretaryPassword,
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown while the screen is still checking whether any account
/// exists.
///
/// A skeleton rather than a spinner, because this state is short and the form
/// it stands in for does not then jump when the real form arrives.
class AuthFormSkeleton extends StatelessWidget {
  const AuthFormSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        AppSkeleton(width: 44, height: 44, radius: 13),
        SizedBox(height: 18),
        AppSkeleton(width: 160, height: 30),
        SizedBox(height: 12),
        AppSkeleton(width: 290, height: 16),
        SizedBox(height: 30),
        AppSkeleton(height: 48),
        SizedBox(height: 18),
        AppSkeleton(height: 48),
        SizedBox(height: 26),
        AppSkeleton(height: 50),
      ],
    );
  }
}
