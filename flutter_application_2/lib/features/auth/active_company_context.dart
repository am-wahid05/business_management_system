import 'package:flutter/foundation.dart';

import 'auth_models.dart';

/// The single in-memory source for the authenticated user and active company.
class ActiveCompanyContext extends ValueNotifier<AppUser?> {
  ActiveCompanyContext([AppUser? user]) : super(user);

  String? get companyId => value?.companyId;
  String? get companyName => value?.companyName;
  String? get logoPath => value?.companyLogoPath;
}
