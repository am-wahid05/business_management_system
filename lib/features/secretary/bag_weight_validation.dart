/// Parses and validates the bag weights entered on the receiving screen's
/// weighing sheet.
///
/// This is the single source of truth for the bag-weight validation contract
/// shared by [NewReceivingScreen] and its tests.
library;

/// Thrown when entered bag weights cannot be accepted.
class BagWeightValidationException implements Exception {
  const BagWeightValidationException(this.message);

  /// The user-facing description of what is wrong with the entered weights.
  final String message;

  @override
  String toString() => 'BagWeightValidationException: $message';
}

/// Parses the raw contents of the weighing sheet's weight boxes into the list
/// of bag weights that will be saved.
///
/// Validation rules (unchanged from [NewReceivingScreen]'s original inline
/// implementation):
///
/// * Each entry is trimmed. Empty and whitespace-only entries are unused
///   weight boxes, so they are skipped and never treated as zero-weight bags.
/// * Every remaining entry must parse to a finite number greater than zero,
///   otherwise a [BagWeightValidationException] is thrown.
/// * If no weight was entered at all, a [BagWeightValidationException] whose
///   message mentions "at least one bag weight" is thrown, so the bag count
///   is never zero.
List<double> parseEnteredBagWeights(List<String> enteredWeights) {
  final weights = <double>[];
  for (final rawEntry in enteredWeights) {
    final entry = rawEntry.trim();
    if (entry.isEmpty) {
      // Unused weight box, not a zero-weight bag.
      continue;
    }
    final weight = double.tryParse(entry);
    if (weight == null || !weight.isFinite || weight <= 0) {
      throw const BagWeightValidationException('Bag weights must be numbers greater than zero.');
    }
    weights.add(weight);
  }
  if (weights.isEmpty) {
    throw const BagWeightValidationException('Enter at least one bag weight before saving.');
  }
  return weights;
}
