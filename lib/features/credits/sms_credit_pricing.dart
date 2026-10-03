/// SMS credit pricing and top-up quantity validation.
///
/// Money is handled exclusively as integer minor units ("pesewas"). One SMS
/// credit costs GH 0.05, which is exactly 5 pesewas. No floating point value is
/// ever produced for an amount, so a total can never drift by a rounding error.
library;

/// Minor units in one Ghanaian Cedi (100 pesewas).
const int minorUnitsPerCedi = 100;

/// Integer pesewas charged for one SMS credit: GH 0.05.
const int pesewasPerCredit = 5;

/// Largest single top-up, to reject obviously unreasonable or malformed input.
const int maxTopUpCredits = 1000000;

/// The prominently promoted package.
const int recommendedTopUpCredits = 10000;

/// Ghana uses the Ghanaian Cedi.
const String topUpCurrency = 'GHS';

/// Why a requested top-up quantity cannot be used.
enum CreditQuantityError { empty, notAnInteger, notPositive, tooLarge }

/// The outcome of validating a top-up request.
class CreditQuantityResult {
  const CreditQuantityResult._(this.credits, this.error);

  const CreditQuantityResult.valid(int credits) : this._(credits, null);

  /// The validated whole-credit amount, or null when invalid.
  final int? credits;
  final CreditQuantityError? error;

  bool get isValid => error == null;

  /// A message suitable for showing directly to the user.
  String? get message {
    switch (error) {
      case null:
        return null;
      case CreditQuantityError.empty:
        return 'Enter the number of SMS credits you want to buy.';
      case CreditQuantityError.notAnInteger:
        return 'Credits must be a whole number. Decimals are not allowed.';
      case CreditQuantityError.notPositive:
        return 'Credits must be at least 1.';
      case CreditQuantityError.tooLarge:
        return 'That is too many credits. Please contact support for a large '
            'top up.';
    }
  }
}

/// Validates raw top-up input as whole credits.
///
/// Accepts only a positive whole number up to [maxTopUpCredits]. Thousands
/// separators are tolerated because users type them, but a decimal point, a
/// negative value, zero and an implausibly large value are all rejected.
CreditQuantityResult validateCreditQuantity(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) {
    return const CreditQuantityResult._(null, CreditQuantityError.empty);
  }
  // Reject anything that is not digits once separators are stripped. This also
  // rejects '-5', '5.5', '1e3', 'abc' and any stray sign.
  final digitsOnly = text.replaceAll(RegExp(r'[\s, ]'), '');
  if (digitsOnly.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(digitsOnly)) {
    return const CreditQuantityResult._(null, CreditQuantityError.notAnInteger);
  }
  final credits = int.tryParse(digitsOnly);
  if (credits == null) {
    return const CreditQuantityResult._(null, CreditQuantityError.tooLarge);
  }
  if (credits < 1) {
    return const CreditQuantityResult._(null, CreditQuantityError.notPositive);
  }
  if (credits > maxTopUpCredits) {
    return const CreditQuantityResult._(null, CreditQuantityError.tooLarge);
  }
  return CreditQuantityResult.valid(credits);
}

/// The amount in integer pesewas for [credits].
///
/// This is the single place a payment amount is derived. The server recomputes
/// it independently; the value here is only for display.
int amountMinorForCredits(int credits) => credits * pesewasPerCredit;

/// Formats an integer pesewa amount as a currency string, for example
/// GH 500.00. Built from the integer value, so no float rounding is involved.
String formatCediMinor(int amountMinor) {
  final cedis = amountMinor ~/ minorUnitsPerCedi;
  final pesewas = (amountMinor % minorUnitsPerCedi).abs();
  final whole = cedis.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
  return 'GH₵$whole.${pesewas.toString().padLeft(2, '0')}';
}

/// The formatted total for a top-up of [credits].
String formatTopUpTotal(int credits) =>
    formatCediMinor(amountMinorForCredits(credits));
