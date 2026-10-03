import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receiving_service.dart';

enum ImportField {
  date,
  supplierId,
  supplierName,
  supplierType,
  town,
  district,
  region,
  productId,
  productName,
  recordedBy,
  totalWeight,
  bagWeights,
}

class ImportWorkbook {
  const ImportWorkbook({required this.filename, required this.sheets});

  final String filename;
  final Map<String, ImportSheet> sheets;
}

class ImportSheet {
  const ImportSheet({
    required this.name,
    required this.headers,
    required this.rows,
  });

  final String name;
  final List<String> headers;
  final List<List<String>> rows;
}

class ImportMapping {
  const ImportMapping(this.columns);

  final Map<ImportField, String?> columns;

  String? column(ImportField field) => columns[field];
}

class ImportRowResult {
  const ImportRowResult({
    required this.rowNumber,
    this.delivery,
    this.error,
    this.warning,
  });

  final int rowNumber;
  final Delivery? delivery;
  final String? error;
  final String? warning;

  bool get isValid => delivery != null && error == null;
}

class ImportValidation {
  const ImportValidation({required this.rows});

  final List<ImportRowResult> rows;

  int get validCount =>
      rows.where((row) => row.isValid && row.warning == null).length;
  int get warningCount =>
      rows.where((row) => row.isValid && row.warning != null).length;
  int get failedCount => rows.where((row) => !row.isValid).length;
}

class ImportSummary {
  const ImportSummary({
    required this.filename,
    required this.rowsTotal,
    required this.imported,
    required this.skipped,
    required this.failed,
  });

  final String filename;
  final int rowsTotal;
  final int imported;
  final int skipped;
  final int failed;
}

class ExcelImportService {
  ExcelImportService({
    required this.database,
    required this.deliveryRepository,
    required this.userId,
    this.companyIdProvider,
    this.receivingService,
  });

  final Database database;
  final DeliveryRepository deliveryRepository;
  final String userId;
  final String? Function()? companyIdProvider;
  final ReceivingService? receivingService;

  ImportWorkbook readWorkbook(Uint8List bytes, String filename) {
    final workbook = Excel.decodeBytes(bytes);
    final sheets = <String, ImportSheet>{};
    for (final entry in workbook.tables.entries) {
      final sourceRows = entry.value.rows;
      if (sourceRows.isEmpty) continue;
      final headers = sourceRows.first
          .map((cell) => _stringValue(cell?.value))
          .toList();
      final rows = sourceRows
          .skip(1)
          .map((row) => row.map((cell) => _stringValue(cell?.value)).toList())
          .toList();
      sheets[entry.key] = ImportSheet(
        name: entry.key,
        headers: headers,
        rows: rows,
      );
    }
    if (sheets.isEmpty) {
      throw StateError('The workbook contains no readable sheets');
    }
    return ImportWorkbook(filename: filename, sheets: sheets);
  }

  ImportValidation validate(ImportSheet sheet, ImportMapping mapping) {
    final results = <ImportRowResult>[];
    for (var index = 0; index < sheet.rows.length; index++) {
      final row = sheet.rows[index];
      try {
        final date = _date(
          _value(sheet, row, mapping.column(ImportField.date)),
        );
        final supplierId = _value(
          sheet,
          row,
          mapping.column(ImportField.supplierId),
        );
        final supplierName = _required(
          _value(sheet, row, mapping.column(ImportField.supplierName)),
          'Supplier name',
        );
        final productId = _required(
          _value(sheet, row, mapping.column(ImportField.productId)),
          'Product ID',
        );
        final productName = _required(
          _value(sheet, row, mapping.column(ImportField.productName)),
          'Product name',
        );
        final weights = _weights(sheet, row, mapping);
        final supplierType =
            _value(
              sheet,
              row,
              mapping.column(ImportField.supplierType),
            ).toLowerCase().contains('aggreg')
            ? SupplierType.aggregator
            : SupplierType.farmer;
        final delivery = Delivery(
          id: 'import-${DateTime.now().microsecondsSinceEpoch}-$index',
          supplier: Supplier(
            id: supplierId,
            name: supplierName,
            type: supplierType,
            town: _value(sheet, row, mapping.column(ImportField.town)),
            district: _value(sheet, row, mapping.column(ImportField.district)),
            region: _value(sheet, row, mapping.column(ImportField.region)),
          ),
          product: Product(id: productId, name: productName),
          recordedAt: date,
          bagWeights: weights,
          // A spreadsheet's recorder label is not a Supabase user identity.
          // The authenticated importer is assigned by ReceivingService when
          // it creates the new record; historical rows are never inferred.
          recordedByUserId: null,
          companyId: companyIdProvider?.call(),
        );
        results.add(ImportRowResult(rowNumber: index + 2, delivery: delivery));
      } on FormatException catch (error) {
        results.add(
          ImportRowResult(rowNumber: index + 2, error: error.message),
        );
      } on ArgumentError catch (error) {
        results.add(
          ImportRowResult(rowNumber: index + 2, error: error.message),
        );
      }
    }
    return ImportValidation(rows: results);
  }

  Future<ImportValidation> validateAsync(
    ImportSheet sheet,
    ImportMapping mapping,
  ) async {
    final initial = validate(sheet, mapping);
    final results = <ImportRowResult>[];
    for (final result in initial.rows) {
      if (!result.isValid) {
        results.add(result);
        continue;
      }
      final delivery = result.delivery!;
      final duplicate = await deliveryRepository.hasLikelyDuplicate(
        recordedAt: delivery.recordedAt,
        supplierId: delivery.supplier.id,
        supplierName: delivery.supplier.name,
        productId: delivery.product.id,
        totalWeight: delivery.totalWeight,
      );
      results.add(
        ImportRowResult(
          rowNumber: result.rowNumber,
          delivery: delivery,
          warning: duplicate
              ? 'Likely duplicate of an existing delivery; it will be skipped.'
              : null,
        ),
      );
    }
    return ImportValidation(rows: results);
  }

  Future<ImportSummary> importValid(
    String filename,
    ImportValidation validation,
  ) async {
    if (companyIdProvider != null && companyIdProvider!() == null) {
      throw StateError(
        'Select an active company before importing business data.',
      );
    }
    var imported = 0;
    var skipped = validation.warningCount;
    var failed = validation.failedCount;
    for (final result in validation.rows.where(
      (row) => row.isValid && row.warning == null,
    )) {
      final delivery = result.delivery!;
      if (await deliveryRepository.hasLikelyDuplicate(
        recordedAt: delivery.recordedAt,
        supplierId: delivery.supplier.id,
        supplierName: delivery.supplier.name,
        productId: delivery.product.id,
        totalWeight: delivery.totalWeight,
      )) {
        skipped++;
        continue;
      }
      try {
        final receiving = receivingService;
        if (receiving == null) {
          await deliveryRepository.save(delivery);
        } else {
          await receiving.saveDelivery(
            supplierId: delivery.supplier.id,
            supplierName: delivery.supplier.name,
            supplierType: delivery.supplier.type,
            town: delivery.supplier.town,
            district: delivery.supplier.district,
            region: delivery.supplier.region,
            selectedSupplier: null,
            delivery: delivery,
          );
        }
        imported++;
      } on Object {
        failed++;
      }
    }
    await database.insert('import_logs', {
      'id': 'import-log-${DateTime.now().microsecondsSinceEpoch}',
      'filename': filename,
      'imported_at': DateTime.now().toIso8601String(),
      'imported_by_user_id': userId,
      if (companyIdProvider != null) 'company_id': companyIdProvider!(),
      'rows_total': validation.rows.length,
      'rows_imported': imported,
      'rows_skipped': skipped,
      'rows_failed': failed,
    });
    return ImportSummary(
      filename: filename,
      rowsTotal: validation.rows.length,
      imported: imported,
      skipped: skipped,
      failed: failed,
    );
  }

  static String _value(ImportSheet sheet, List<String> row, String? header) {
    if (header == null) return '';
    final index = sheet.headers.indexOf(header);
    return index >= 0 && index < row.length ? row[index].trim() : '';
  }

  static String _required(String value, String label) =>
      value.isEmpty ? (throw FormatException('$label is required')) : value;

  static DateTime _date(String value) =>
      DateTime.tryParse(value) ??
      (throw FormatException('Invalid date: $value'));

  static List<double> _weights(
    ImportSheet sheet,
    List<String> row,
    ImportMapping mapping,
  ) {
    final raw = _value(sheet, row, mapping.column(ImportField.bagWeights));
    final values = raw
        .split(RegExp(r'[,;|]'))
        .map((value) => double.tryParse(value.trim()))
        .whereType<double>()
        .toList();
    final total = double.tryParse(
      _value(sheet, row, mapping.column(ImportField.totalWeight)),
    );
    if (values.isEmpty && total != null && total > 0) return [total];
    if (values.isEmpty ||
        values.any((weight) => !weight.isFinite || weight <= 0)) {
      throw FormatException(
        'At least one valid positive bag weight is required',
      );
    }
    return values;
  }

  static String _stringValue(Object? value) => value?.toString() ?? '';
}
