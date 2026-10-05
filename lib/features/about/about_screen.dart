import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_info.dart';
import '../../app/app_navigation.dart';
import '../../app/app_responsive.dart';
import 'about_row.dart';

/// Information about the SOFTWARE itself.
///
/// This page is identical for every company. It reads only from [AppInfo], which
/// is a compile-time constant, and never from the active company, the
/// `companies` table, or a company logo. That is deliberate: sourcing any of it
/// from tenant data would show one company's name, logo or contact details to
/// another company's user. Company information lives in Company Settings and in
/// the company brand mark in the navigation drawer, and the two are kept
/// strictly separate.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final website = AppInfo.websiteUrl;
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: shellDrawerFor(context),
      body: SafeArea(
        child: SingleChildScrollView(
          child: AppResponsive(
            maxWidth: 560,
            builder: (context, size) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Center(child: _SoftwareMark(theme: theme)),
                const SizedBox(height: 20),
                Text(
                  AppInfo.appName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Version ${AppInfo.version}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Developed by ${AppInfo.developer}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                // The website row is always present so the layout does not
                // change when a URL is added later. While the destination is
                // unset the row is inert: no URL is displayed, no placeholder
                // text, and nothing is invented.
                AboutRow(
                  icon: Icons.language_outlined,
                  label: 'Website',
                  isEnabled: website != null,
                  onTap: website == null
                      ? null
                      : () => _open(context, Uri.parse(website)),
                ),
                AboutRow(
                  icon: Icons.chat_outlined,
                  label: 'WhatsApp',
                  // The number is never shown. The row is labelled "WhatsApp"
                  // and opens a conversation; that is all a user ever sees.
                  isEnabled: true,
                  onTap: () => _open(context, AppInfo.whatsappUri),
                ),
                const SizedBox(height: 24),
                Text(
                  'This page describes the software only. Your company name, '
                  'logo and contact details are managed separately in Company '
                  'Settings.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Opens [uri], degrading quietly when the device cannot handle it.
  ///
  /// WhatsApp in particular may simply not be installed, and a missing app must
  /// not crash the app or leave the user on a dead screen. The number is never
  /// echoed into the failure message.
  static Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final theme = Theme.of(context);
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (launched) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not open that. Please check that the app is installed on this '
          'device.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// The application's own mark, drawn from the app theme.
///
/// This is intentionally not the company logo: the company logo is tenant data
/// and must never appear on a page that is the same for everyone.
class _SoftwareMark extends StatelessWidget {
  const _SoftwareMark({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(
        Icons.business_center_outlined,
        size: 44,
        color: theme.colorScheme.primary,
      ),
    );
  }
}
