/// The single source of truth for the SOFTWARE's own information.
///
/// Everything here is about the application itself, not about any company. It is
/// identical for every tenant, so nothing in this file may ever be derived from
/// [ActiveCompanyContext], the `companies` table, or a company logo. Company
/// branding is a separate, tenant-scoped concern and must not be mixed in here:
/// doing so would leak one company's name or contact details to another.
///
/// The version mirrors the `version:` field in pubspec.yaml, which is the value
/// the Flutter tool stamps into the built binary. package_info_plus is not a
/// dependency of this project, so this constant is kept as the one place the
/// displayed version is written, and it must be updated alongside pubspec.yaml.
abstract final class AppInfo {
  /// The product name shown in the About page and the window title.
  static const String appName = 'Business Management System';

  /// The marketing version, matching `version: 1.0.0+1` in pubspec.yaml.
  ///
  /// The build suffix is deliberately excluded: "+1" is a build counter that
  /// means nothing to a user, so the About page shows the plain 1.0.0.
  static const String version = '1.0.0';

  /// The author of the software.
  static const String developer = 'Abdul Wahid';

  /// The public website, or null while it is not yet decided.
  ///
  /// There is deliberately no placeholder string here. Until a real URL exists
  /// the About page renders the "Website" row with no destination and no
  /// invented link, rather than showing a made-up address or a "coming soon"
  /// message. Setting this to a real https URL is the only change needed later,
  /// and the row becomes tappable on its own.
  static const String? websiteUrl = null;

  /// The developer contact number in local Ghanaian format.
  ///
  /// This is private to this library on purpose. It is only ever used to build
  /// the WhatsApp deep link, and it is never rendered as visible text anywhere
  /// in the app, so the About page cannot display it by accident.
  static const String _whatsappLocalNumber = '0530466346';

  /// The WhatsApp destination, in the international form wa.me requires.
  ///
  /// Ghana's country code is +233 and the local number already carries a leading
  /// 0, which is dropped when converting. The result is a URL, not a display
  /// string, so the number stays out of the rendered interface.
  static final Uri whatsappUri = Uri.parse(
    'https://wa.me/233${_whatsappLocalNumber.substring(1)}',
  );
}