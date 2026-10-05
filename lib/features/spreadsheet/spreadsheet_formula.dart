/// Why a cell could not be evaluated.
///
/// Every failure is reported to the user instead of throwing, so a typo in a
/// formula can never crash the grid.
enum FormulaError {
  /// The text does not start with `=`.
  notAFormula,

  /// The function name is not one of the supported ones.
  unknownFunction,

  /// A range such as `D2:D20` is malformed.
  badRange,

  /// A referenced cell is outside the grid.
  outOfRange,

  /// Division by zero.
  divideByZero,

  /// A referenced cell is not a number.
  notANumber,

  /// The formula text could not be understood.
  malformed,
}

/// The outcome of evaluating one cell.
class FormulaResult {
  const FormulaResult._({
    this.value,
    this.error,
    this.text,
    this.isFormula = false,
  });

  const FormulaResult.number(double value) : this._(value: value);

  const FormulaResult.text(String value) : this._(text: value, isFormula: true);

  const FormulaResult.failure(FormulaError error) : this._(error: error);

  /// A cell that holds a plain value rather than a formula.
  factory FormulaResult.literal(Object? value) => FormulaResult._(
    value: value is num ? value.toDouble() : null,
    text: '$value',
  );

  final double? value;
  final String? text;
  final FormulaError? error;
  final bool isFormula;

  bool get isFailure => error != null;

  /// The message shown under the cell when a formula cannot be evaluated.
  String get errorLabel => switch (error) {
    null => '',
    FormulaError.notAFormula => 'Not a formula',
    FormulaError.unknownFunction => 'Unknown function',
    FormulaError.badRange => 'Invalid range',
    FormulaError.outOfRange => 'Cell is outside the sheet',
    FormulaError.divideByZero => 'Cannot divide by zero',
    FormulaError.notANumber => 'Value is not a number',
    FormulaError.malformed => 'Formula is not valid',
  };
}

/// Where a formula can read a value from.
///
/// The grid supplies this so the formula engine never needs to know about
/// widgets, rows or the database.
abstract interface class FormulaGrid {
  /// The number stored in a cell, or null when it is empty or not numeric.
  double? numberAt(int row, int column);

  /// The text stored in a cell.
  String textAt(int row, int column);

  /// How many rows and columns exist.
  int get rowCount;
  int get columnCount;

  /// The spreadsheet column letter for a zero-based column index, so `0` is `A`.
  static String columnLetter(int column) {
    var value = column;
    final letters = StringBuffer();
    do {
      letters.write(String.fromCharCode(65 + value % 26));
      value = value ~/ 26 - 1;
    } while (value >= 0);
    return letters.toString().split('').reversed.join();
  }

  /// Converts a column reference such as `D` into a zero-based index.
  static int? columnFromLetter(String letters) {
    if (letters.isEmpty) return null;
    var value = 0;
    for (final code in letters.toUpperCase().codeUnits) {
      if (code < 65 || code > 90) return null;
      value = value * 26 + (code - 64);
    }
    return value - 1;
  }
}

/// Evaluates the small formula subset the business grid supports.
///
/// Only `SUM`, `AVERAGE`, `COUNT`, `MIN`, `MAX` and the `+ - * /` operators are
/// understood. A formula is display-only: its result is never written back to a
/// row, so a formula can never become an official weight, bag count or total.
class FormulaEvaluator {
  const FormulaEvaluator(this.grid);

  final FormulaGrid grid;

  static final RegExp _cell = RegExp(r'^\$?([A-Za-z]{1,3})\$?([0-9]{1,7})$');
  static final RegExp _range = RegExp(
    r'^\$?([A-Za-z]{1,3})\$?([0-9]{1,7}):\$?([A-Za-z]{1,3})\$?([0-9]{1,7})$',
  );

  /// Evaluates [source]; a plain value is returned unchanged.
  FormulaResult evaluate(String source) {
    final text = source.trim();
    if (text.isEmpty) return FormulaResult.literal('');
    if (!text.startsWith('=')) return FormulaResult.literal(text);
    final body = text.substring(1).trim();
    if (body.isEmpty)
      return const FormulaResult.failure(FormulaError.malformed);

    // A function call such as SUM(D2:D20).
    final call = RegExp(r'^([A-Za-z]+)\((.*)\)$').firstMatch(body);
    if (call != null) {
      return _evaluateFunction(
        call.group(1)!.toUpperCase(),
        call.group(2)!.trim(),
      );
    }
    return _evaluateExpression(body);
  }

  FormulaResult _evaluateFunction(String name, String argument) {
    final values = _collectValues(argument);
    if (values == null) {
      return const FormulaResult.failure(FormulaError.malformed);
    }
    final numbers = <double>[];
    for (final value in values) {
      final number = _toNumber(value);
      if (number != null) numbers.add(number);
    }

    switch (name) {
      case 'SUM':
        return FormulaResult.number(numbers.fold<double>(0, (a, b) => a + b));
      case 'COUNT':
        return FormulaResult.number(numbers.length.toDouble());
      case 'AVERAGE':
        if (numbers.isEmpty) {
          return const FormulaResult.failure(FormulaError.notANumber);
        }
        return FormulaResult.number(
          numbers.reduce((a, b) => a + b) / numbers.length,
        );
      case 'MIN':
        if (numbers.isEmpty) {
          return const FormulaResult.failure(FormulaError.notANumber);
        }
        return FormulaResult.number(numbers.reduce((a, b) => a < b ? a : b));
      case 'MAX':
        if (numbers.isEmpty) {
          return const FormulaResult.failure(FormulaError.notANumber);
        }
        return FormulaResult.number(numbers.reduce((a, b) => a > b ? a : b));
      default:
        return const FormulaResult.failure(FormulaError.unknownFunction);
    }
  }

  FormulaResult _evaluateExpression(String body) {
    // A single operator keeps this small and predictable, and covers the
    // `=D2+E2` style of arithmetic between cells and numbers.
    for (final operator in ['+', '-', '*', '/']) {
      final index = _topLevelIndexOf(body, operator);
      if (index <= 0) continue;
      final left = _operand(body.substring(0, index));
      if (left.error != null) {
        return FormulaResult.failure(left.error!);
      }
      final right = _operand(body.substring(index + 1));
      if (right.error != null) {
        return FormulaResult.failure(right.error!);
      }
      final leftValue = left.value!;
      final rightValue = right.value!;
      switch (operator) {
        case '+':
          return FormulaResult.number(leftValue + rightValue);
        case '-':
          return FormulaResult.number(leftValue - rightValue);
        case '*':
          return FormulaResult.number(leftValue * rightValue);
        default:
          return rightValue == 0
              ? const FormulaResult.failure(FormulaError.divideByZero)
              : FormulaResult.number(leftValue / rightValue);
      }
    }
    // A bare cell reference such as `=D2`.
    final single = _operand(body);
    if (single.error != null) {
      return FormulaResult.failure(single.error!);
    }
    return FormulaResult.number(single.value!);
  }

  /// Finds the first [operator] in the expression.
  ///
  /// A cell reference such as `D1` can never contain `+ - * /`, so any operator
  /// found is a real one: `=A1-B1` is a subtraction, not a stray dash.
  int _topLevelIndexOf(String text, String operator) {
    final index = text.indexOf(operator);
    // An operator at position 0 would be a leading sign, not a binary operator.
    return index <= 0 ? -1 : index;
  }

  _Operand _operand(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const _Operand.malformed();
    final reference = _cell.firstMatch(text);
    if (reference != null) {
      // The reference is well formed, so a non-numeric cell is a VALUE problem
      // rather than a broken expression. `=A1-B1` where A1 holds text is
      // therefore reported as "not a number", not as a malformed formula.
      final value = _toNumber(_valueOf(reference));
      return value == null
          ? const _Operand.notNumber()
          : _Operand.number(value);
    }
    final literal = _toNumber(text);
    return literal == null
        ? const _Operand.malformed()
        : _Operand.number(literal);
  }

  /// Reads the values an argument refers to: a cell, a range, a literal, or a
  /// comma separated list of those.
  List<Object?>? _collectValues(String argument) {
    final text = argument.trim();
    if (text.isEmpty) return const [];

    final range = _range.firstMatch(text);
    if (range != null) return _valuesInRange(range);

    final parts = text.split(',').map((part) => part.trim()).toList();
    final values = <Object?>[];
    for (final part in parts) {
      final cell = _cell.firstMatch(part);
      values.add(cell != null ? _valueOf(cell) : part);
    }
    return values;
  }

  List<Object?>? _valuesInRange(RegExpMatch range) {
    final startColumn = FormulaGrid.columnFromLetter(range.group(1)!);
    final endColumn = FormulaGrid.columnFromLetter(range.group(3)!);
    if (startColumn == null || endColumn == null) return null;
    final startRow = int.parse(range.group(2)!);
    final endRow = int.parse(range.group(4)!);
    if (startRow < 1 || endRow < 1 || endRow < startRow) return null;

    // A range that leaves the grid is treated as empty rather than an error,
    // so a formula never crashes the grid.
    final values = <Object?>[];
    for (var row = startRow - 1; row <= endRow - 1; row++) {
      for (var column = startColumn; column <= endColumn; column++) {
        if (row >= grid.rowCount || column >= grid.columnCount) continue;
        values.add(grid.numberAt(row, column));
      }
    }
    return values;
  }

  Object? _valueOf(RegExpMatch match) {
    final column = FormulaGrid.columnFromLetter(match.group(1)!);
    final row = int.parse(match.group(2)!);
    if (column == null || row < 1) return null;
    if (row - 1 >= grid.rowCount || column >= grid.columnCount) return null;
    return grid.numberAt(row - 1, column);
  }

  double? _toNumber(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }
}

/// One operand of an arithmetic expression.
///
/// This keeps a malformed expression apart from a well formed reference to a
/// non-numeric cell: the first is a syntax error, the second is a value error,
/// and the user needs to be told which one it is.
class _Operand {
  const _Operand.number(this.value) : error = null;
  const _Operand.notNumber() : value = null, error = FormulaError.notANumber;
  const _Operand.malformed() : value = null, error = FormulaError.malformed;

  final double? value;
  final FormulaError? error;
}
