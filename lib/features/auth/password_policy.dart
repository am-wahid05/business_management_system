/// The password rules the whole application applies.
///
/// The same rules are used by Change Password, Reset Password and the
/// Forgot Password confirmation copy, so a password accepted on one screen is
/// never refused on another. This is deliberately pure Dart with no Flutter or
/// Supabase dependency, which is what makes it directly testable.
abstract final class PasswordPolicy {
  /// The minimum number of characters.
  static const int minLength = 8;

  /// The requirement text shown under the password fields.
  static const String requirementText =
      'Use at least 8 characters, with an uppercase letter, a lowercase letter '
      'and a number.';

  /// Validates a new password, returning the first problem or null when valid.
  ///
  /// The order of the checks is the order the messages are most useful in, so
  /// the user is told about a short password before being told it is also
  /// missing an uppercase letter.
  static String? validate(String? password) {
    final value = password ?? '';
    if (value.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (!value.contains(RegExp('[A-Z]'))) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!value.contains(RegExp('[a-z]'))) {
      return 'Password must contain at least one lowercase letter.';
    }
    if (!value.contains(RegExp('[0-9]'))) {
      return 'Password must contain at least one number.';
    }
    return null;
  }

  /// Whether a new password satisfies every rule.
  static bool isValid(String? password) => validate(password) == null;

  /// Validates that the two entries match.
  ///
  /// This is separate from [validate] so a mismatched confirmation never
  /// reports "password is too weak" first, which would be confusing when both
  /// fields are correct in content and simply differ.
  static String? validateMatch(String? password, String? confirmation) {
    if (password != confirmation) return 'Passwords do not match.';
    return null;
  }
}
