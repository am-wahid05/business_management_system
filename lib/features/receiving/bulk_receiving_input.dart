import '../imports/excel_cell_parser.dart';

/// A weighing-bridge entry that cannot be saved, with a user-facing message.
///
/// This is a pure data concern, kept out of any screen so the importer and the
/// receiving form validate a bulk row with exactly the same rules.
class BulkReceivingValidationException implements Exception {
  const BulkReceivingValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The validated values of a weighing-bridge form.
class BulkReceivingInput {
  const BulkReceivingInput({
    required this.bagCount,
    required this.totalWeight,
    this.notes,
  });

  final int bagCount;
  final double totalWeight;
  final String? notes;
}

/// Validates a weighing-bridge entry.
///
/// A bulk record stores one total and a bag count, so there are no bag weights
/// to validate and none are ever invented. The bag count must be a whole number
/// greater than zero and the total weight must be a number greater than zero.
BulkReceivingInput parseBulkReceivingInput({
  required String bags,
  required String totalWeight,
  String? notes,
}) {
  final bagCount = int.tryParse(bags.trim());
  if (bagCount == null) {
    throw const BulkReceivingValidationException(
      'Enter the number of bags as a whole number.',
    );
  }
  if (bagCount <= 0) {
    throw const BulkReceivingValidationException(
      'Number of bags must be greater than zero.',
    );
  }
  final total = parseImportNumber(totalWeight);
  if (total == null) {
    throw const BulkReceivingValidationException(
      'Enter the total weight from the scale.',
    );
  }
  if (!total.isFinite || total <= 0) {
    throw const BulkReceivingValidationException(
      'Total weight must be greater than zero.',
    );
  }
  final trimmedNotes = notes?.trim();
  return BulkReceivingInput(
    bagCount: bagCount,
    totalWeight: total,
    notes: trimmedNotes == null || trimmedNotes.isEmpty ? null : trimmedNotes,
  );
}
