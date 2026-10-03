import 'spreadsheet_state_store.dart';

export 'spreadsheet_state_store.dart' show CellMerge;

/// Why a merge request was refused.
enum MergeFailure { none, singleCell, notMerged, overlapsExisting }

/// The outcome of a merge or unmerge request.
class MergeResult {
  const MergeResult.ok(this.merge)
    : failure = MergeFailure.none,
      message = null;
  const MergeResult.refused(this.failure, this.message) : merge = null;

  final CellMerge? merge;
  final MergeFailure failure;
  final String? message;

  bool get isSuccess => merge != null;
}

/// Validates and holds the merged ranges for one company's sheet.
///
/// A merge is stored as the keys of its top-left and bottom-right cells, so it
/// stays attached to the same rows when the grid is sorted or filtered.
///
/// Overlapping merges are refused rather than resolved, because a partial
/// overlap has no single correct meaning and allowing one would corrupt the
/// sheet. Re-merging the exact same range is treated as an overlap too, so the
/// same range is never stored twice.
class MergeManager {
  MergeManager(this._merges);

  List<CellMerge> _merges;

  List<CellMerge> get merges => List.unmodifiable(_merges);

  void replaceAll(Iterable<CellMerge> value) {
    _merges = value.toList(growable: true);
  }

  /// The visual (top, left, bottom, right) of a merge, or null when one of its
  /// rows is no longer in the grid.
  static (int, int, int, int)? bounds(CellMerge merge, List<String> rowKeys) {
    final top = rowKeys.indexOf(merge.anchorRowKey);
    final bottom = rowKeys.indexOf(merge.endRowKey);
    if (top < 0 || bottom < 0) return null;
    return (
      top < bottom ? top : bottom,
      merge.anchorColumn < merge.endColumn
          ? merge.anchorColumn
          : merge.endColumn,
      top < bottom ? bottom : top,
      merge.anchorColumn < merge.endColumn
          ? merge.endColumn
          : merge.anchorColumn,
    );
  }

  /// True when two merges share at least one cell in the current visual order.
  static bool overlaps(CellMerge left, CellMerge right, List<String> rowKeys) {
    final a = bounds(left, rowKeys);
    final b = bounds(right, rowKeys);
    if (a == null || b == null) return false;
    return a.$1 <= b.$3 && a.$3 >= b.$1 && a.$2 <= b.$4 && a.$4 >= b.$2;
  }

  /// Merges the rectangle between two cells, in visual grid order.
  ///
  /// [rowKeys] is the row keys in the order they appear in the grid, so a
  /// selection still merges the cells the user actually selected.
  MergeResult merge({
    required List<String> rowKeys,
    required int startRow,
    required int startColumn,
    required int endRow,
    required int endColumn,
  }) {
    final top = startRow <= endRow ? startRow : endRow;
    final bottom = startRow <= endRow ? endRow : startRow;
    final left = startColumn <= endColumn ? startColumn : endColumn;
    final right = startColumn <= endColumn ? endColumn : startColumn;

    if (top == bottom && left == right) {
      return const MergeResult.refused(
        MergeFailure.singleCell,
        'Select more than one cell to merge.',
      );
    }
    if (top < 0 || left < 0 || bottom >= rowKeys.length) {
      return const MergeResult.refused(
        MergeFailure.singleCell,
        'That selection is not a valid range in the grid.',
      );
    }

    final candidate = CellMerge(
      anchorRowKey: rowKeys[top],
      anchorColumn: left,
      endRowKey: rowKeys[bottom],
      endColumn: right,
    );
    for (final existing in _merges) {
      if (overlaps(existing, candidate, rowKeys)) {
        return const MergeResult.refused(
          MergeFailure.overlapsExisting,
          'Those cells overlap an existing merged range. Unmerge it first.',
        );
      }
    }
    _merges = [..._merges, candidate];
    return MergeResult.ok(candidate);
  }

  /// Removes the merge anchored on a cell.
  MergeResult unmerge({
    required List<String> rowKeys,
    required int row,
    required int column,
  }) {
    if (row < 0 || row >= rowKeys.length) {
      return const MergeResult.refused(
        MergeFailure.singleCell,
        'That cell is not part of the grid.',
      );
    }
    final key = rowKeys[row];
    final existing = _merges
        .where((m) => m.anchorRowKey == key && m.anchorColumn == column)
        .toList();
    if (existing.isEmpty) {
      return const MergeResult.refused(
        MergeFailure.notMerged,
        'These cells are not merged.',
      );
    }
    _merges = _merges.where((m) => !existing.contains(m)).toList(growable: true);
    return MergeResult.ok(existing.first);
  }

  /// The merge covering a cell, or null when the cell is not merged.
  CellMerge? mergeCovering(List<String> rowKeys, int row, int column) {
    if (row < 0 || row >= rowKeys.length) return null;
    for (final merge in _merges) {
      final box = bounds(merge, rowKeys);
      if (box == null) continue;
      if (row >= box.$1 && row <= box.$3 && column >= box.$2 && column <= box.$4) {
        return merge;
      }
    }
    return null;
  }

  /// True when the cell is inside a merge but is not its anchor, so it must not
  /// be edited directly.
  bool isCoveredByMerge(List<String> rowKeys, int row, int column) {
    final merge = mergeCovering(rowKeys, row, column);
    if (merge == null) return false;
    return merge.anchorRowKey != rowKeys[row] || merge.anchorColumn != column;
  }
}
