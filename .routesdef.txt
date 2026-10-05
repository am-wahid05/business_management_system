abstract final class AppRoutes {
  static const login = '/';
  static const resetPassword = '/reset-password';
  static const secretaryDashboard = '/secretary';
  static const newReceiving = '/secretary/new-receiving';
  static const todaysRecords = '/secretary/todays-records';
  static const secretaryPrintRecords = '/secretary/print-records';
  static const secretarySmsCredits = '/secretary/sms-credits';
  static const adminDashboard = '/admin';
  static const suppliers = '/admin/suppliers';
  static const deliveries = '/admin/deliveries';

  /// Recording a new delivery from the Admin workspace.
  ///
  /// Admin and Secretary record deliveries with the same screen and the same
  /// service, but each inside its own shell, so neither user ever lands in the
  /// other one's navigation. The permission check is unchanged: recording a
  /// delivery still requires `AppPermission.receiveDeliveries`.
  static const adminReceiving = '/admin/receiving';
  static const products = '/admin/products';
  static const reports = '/admin/reports';
  static const monthlyReports = '/admin/reports/monthly';
  static const yearlyReports = '/admin/reports/yearly';
  static const statements = '/admin/statements';
  static const excel = '/admin/excel';
  static const excelImport = '/admin/excel/import';

  /// The Excel-like workbook grid, reachable cold so a workbook saved earlier
  /// can be reopened without first re-picking the original file.
  static const workbookGrid = '/admin/excel/spreadsheet';
  static const users = '/admin/users';
  static const settings = '/admin/settings';
  static const assistant = '/admin/assistant';
  static const analytics = '/admin/analytics';
  static const spreadsheet = '/admin/spreadsheet';
  static const billing = '/admin/billing';
  static const about = '/admin/about';

  /// Account-level settings, available to every signed-in user.
  ///
  /// Changing your own password is an account action, not a company
  /// management one, so it deliberately does not live only under the admin
  /// settings route: a secretary must be able to reach it without being given
  /// any company-management permission. It still requires the authenticated
  /// session and the current password, so it can only ever change the
  /// signed-in user's own credentials.
  static const accountSettings = '/account/settings';

  /// Read-only application information, reachable by every signed-in role.
  static const aboutScreen = '/about';
}
