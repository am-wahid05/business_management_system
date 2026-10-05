import '../../domain/models/product.dart';
import 'import_models.dart';

/// Recognised synonyms for each importable field.
///
/// Matching is done on whole tokens, never on raw substrings. The previous
/// implementation used `header.contains(candidate)`, which made almost any
/// header match a field because candidates as short as `id` and `name` appear
/// inside unrelated words.
const Map<ImportField, Set<String>> _fieldSynonyms = {
  ImportField.recordType: {
    'record type',
    'delivery type',
    'receiving type',
    'weighing type',
  },
  ImportField.date: {'date', 'day', 'received', 'receiving', 'delivery date'},
  ImportField.supplierId: {
    'supplier id',
    'supplier code',
    'supplier no',
    'id',
    'code',
  },
  ImportField.supplierName: {
    'supplier',
    'supplier name',
    'name',
    'farmer',
    'customer',
    'supplier full name',
  },
  ImportField.supplierType: {
    'type',
    'supplier type',
    'category',
    'supplier category',
  },
  ImportField.town: {'town', 'location', 'city'},
  ImportField.district: {'district'},
  ImportField.region: {'region'},
  ImportField.productId: {'product id', 'product code', 'commodity code'},
  ImportField.productName: {
    'product',
    'product name',
    'commodity',
    'item',
    'crop',
  },
  ImportField.recordedBy: {
    'recorded by',
    'recorder',
    'staff',
    'secretary',
    'entered by',
  },
  ImportField.totalWeight: {
    'total weight',
    'weight',
    'total kg',
    'gross weight',
    'net weight',
    'weight kg',
    'total',
  },
  // A count of bags is deliberately not listed here: a header such as
  // "Number of Bags" must not be read as a list of bag weights. It maps to its
  // own counting field instead.
  ImportField.bagCount: {
    'number of bags',
    'bags',
    'bag count',
    'no of bags',
    'quantity of bags',
  },
  // Only unambiguous whole-token synonyms. A vague word such as "comment" or
  // "note" would claim unrelated headers, so those are deliberately absent.
  ImportField.notes: {'notes', 'remarks', 'comments'},
  // A weight is only a bag-weight COLLECTION when the header says so in the
  // plural. The singular "bag weight" was dropped because a numbered column
  // such as "Bag 3 Weight" is one specific bag, not the collection, and the
  // subset scorer would otherwise let it outrank the plain "weight" reading.
  ImportField.bagWeights: {'bag weights', 'weights', 'individual weights'},
};

/// Normalises a header into lowercase word tokens.
///
/// `Supplier  ID`, `supplier-id` and `Supplier ID` all become
/// `{supplier, id}`, so punctuation and spacing differences never matter.
Set<String> tokenize(String header) => header
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((token) => token.isNotEmpty)
    .toSet();

int _synonymScore(Set<String> synonymTokens, Set<String> tokens) {
  if (synonymTokens.difference(tokens).isNotEmpty) return 0;
  // An exact whole-header match is the strongest signal.
  return synonymTokens.length == tokens.length
      ? 100 + synonymTokens.length
      : 10 + synonymTokens.length;
}

/// Chooses the importable field a column header most likely represents.

/// Guesses a column mapping for a header row.
///
/// Fields are assigned greedily from the strongest match so that one column is
/// never claimed twice, which is what previously allowed a single `Weight`
/// column to be mapped to both the total and the bag weights.
ImportMapping guessMapping(List<String> headers) {
  final scored = <({ImportField field, String header, int score})>[];
  for (final header in headers) {
    final field = detectFieldForHeader(header);
    if (field == null) continue;
    scored.add((
      field: field,
      header: header,
      score: _bestSynonymScore(field, header),
    ));
  }
  scored.sort((left, right) => right.score.compareTo(left.score));

  final columns = <ImportField, String?>{};
  final usedHeaders = <String>{};
  for (final candidate in scored) {
    if (columns.containsKey(candidate.field)) continue;
    if (usedHeaders.contains(candidate.header)) continue;
    columns[candidate.field] = candidate.header;
    usedHeaders.add(candidate.header);
  }
  return ImportMapping(columns);
}

int _bestSynonymScore(ImportField field, String header) {
  final tokens = tokenize(header);
  var best = 0;
  for (final synonym in _fieldSynonyms[field]!) {
    final score = _synonymScore(tokenize(synonym), tokens);
    if (score > best) best = score;
  }
  return best;
}

/// Finds the row that holds the column headers.
///
/// Real workbooks often start with a title, a blank spacer row, or an
/// "exported by" note. Assuming the header is row 0 therefore mis-reads the
/// file. This scores the first [maxScanRows] rows by how many cells look like
/// known headers and returns the best one, falling back to row 0.
int detectHeaderRow(List<List<String>> rows, {int maxScanRows = 15}) {
  if (rows.isEmpty) return 0;
  final limit = rows.length < maxScanRows ? rows.length : maxScanRows;
  var bestIndex = 0;
  var bestScore = -1;
  for (var index = 0; index < limit; index++) {
    final cells = rows[index];
    if (cells.every((cell) => cell.trim().isEmpty)) continue;
    var recognised = 0;
    for (final cell in cells) {
      if (cell.trim().isEmpty) continue;
      if (detectFieldForHeader(cell) != null) recognised++;
    }
    // A header row is mostly text labels, and at least two of them should be
    // recognisable before the row is trusted.
    final score = recognised * 10 + (recognised >= 2 ? 5 : 0);
    if (score > bestScore) {
      bestScore = score;
      bestIndex = index;
    }
  }
  return bestIndex;
}

/// Resolves a product identifier from a product name when the workbook has no
/// product ID column.
///
/// Matching is done against the company's seeded catalogue, then falls back to
/// a stable slug so an unknown product still imports rather than being dropped.
String? inferProductId(String productName, List<Product> catalogue) {
  final tokens = tokenize(productName);
  if (tokens.isEmpty) return null;
  for (final product in catalogue) {
    if (tokens.containsAll(tokenize(product.name))) return product.id;
  }
  final slug = productName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.isEmpty ? null : slug;
}

///
/// An exact match on the whole normalised header wins. Otherwise the header
/// must contain every token of a synonym, so `Total Weight` cannot be claimed
/// by `supplierName` merely because it contains the letters `name`.
ImportField? detectFieldForHeader(String header) {
  final tokens = tokenize(header);
  if (tokens.isEmpty) return null;

  ImportField? bestField;
  var bestScore = 0;
  for (final entry in _fieldSynonyms.entries) {
    for (final synonym in entry.value) {
      final score = _synonymScore(tokenize(synonym), tokens);
      if (score > bestScore) {
        bestScore = score;
        bestField = entry.key;
      }
    }
  }
  return bestField;
}
