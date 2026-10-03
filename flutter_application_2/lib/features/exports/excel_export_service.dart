import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/delivery.dart';
import '../receiving/delivery_repository.dart';
import '../suppliers/supplier_statement.dart';

class ExcelExportService implements SupplierStatementExporter {
  ExcelExportService(
    this.deliveryRepository, {
    Future<Directory> Function()? directoryProvider,
    this.companyNameProvider,
    this.recorderNamesProvider,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final DeliveryRepository deliveryRepository;
  final String Function()? companyNameProvider;
  final Future<Map<String, String>> Function()? recorderNamesProvider;
  final Future<Directory> Function() _directoryProvider;

  String get _companyPrefix =>
      _safeName(companyNameProvider?.call() ?? 'Company');

  Future<File> exportDaily(DateTime date) async {
    return _write(
      '${_companyPrefix}_Daily_Report_${_datePart(date)}.xlsx',
      await deliveryRepository.forDate(date),
    );
  }

  Future<File> exportMonthly(int year, int month) async {
    final start = DateTime(year, month);
    return _write(
      '${_companyPrefix}_Monthly_Report_${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}.xlsx',
      await deliveryRepository.forRange(start, DateTime(year, month + 1)),
    );
  }

  Future<File> exportYearly(int year) async {
    return _write(
      '${_companyPrefix}_Yearly_Report_$year.xlsx',
      await deliveryRepository.forRange(DateTime(year), DateTime(year + 1)),
    );
  }

  Future<File> exportSupplierHistory(
    String supplierId,
    String supplierName,
  ) async {
    return _write(
      '${_companyPrefix}_Supplier_${_safeName(supplierName)}.xlsx',
      await deliveryRepository.forRange(
        DateTime(2000),
        DateTime(2100),
        supplierId: supplierId,
      ),
    );
  }

  @override
  Future<File> export(SupplierStatement statement) async {
    return _writeStatement(
      '${_companyPrefix}_Statement_${_safeName(statement.supplier.name)}_${_datePart(statement.from)}_${_datePart(statement.to)}.xlsx',
      statement,
    );
  }

  Future<File> exportProductReport(String productId, String productName) async {
    return _write(
      '${_companyPrefix}_Product_${_safeName(productName)}.xlsx',
      await deliveryRepository.forRange(
        DateTime(2000),
        DateTime(2100),
        productId: productId,
      ),
    );
  }

  Future<File> exportSelected(List<String> deliveryIds) async {
    final deliveries = <Delivery>[];
    for (final id in deliveryIds) {
      final delivery = await deliveryRepository.findById(id);
      if (delivery != null) deliveries.add(delivery);
    }
    return _write(
      '${_companyPrefix}_Selected_Deliveries_${_datePart(DateTime.now())}.xlsx',
      deliveries,
    );
  }

  Future<File> _write(String filename, List<Delivery> deliveries) async {
    final recorderNames = await recorderNamesProvider?.call() ?? const {};
    final workbook = Excel.createExcel();
    final sheet = workbook['Receiving'];
    final maxBags = deliveries.fold<int>(
      0,
      (maximum, delivery) =>
          delivery.numberOfBags > maximum ? delivery.numberOfBags : maximum,
    );
    final headers = <String>[
      'Date',
      'Supplier ID',
      'Supplier Name',
      'Supplier Type',
      'Town',
      'District',
      'Region',
      'Product',
      'Number of Bags',
      'Total Weight',
      'Recorded By',
      ...List.generate(
        maxBags,
        (index) => ['Bag ${index + 1} Weight', 'Bag ${index + 1} Recorded By'],
      ).expand((values) => values),
    ];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final delivery in deliveries) {
      sheet.appendRow([
        TextCellValue(_datePart(delivery.recordedAt)),
        TextCellValue(delivery.supplier.id),
        TextCellValue(delivery.supplier.name),
        TextCellValue(delivery.supplier.type.name),
        TextCellValue(delivery.supplier.town),
        TextCellValue(delivery.supplier.district),
        TextCellValue(delivery.supplier.region),
        TextCellValue(delivery.product.name),
        IntCellValue(delivery.numberOfBags),
        DoubleCellValue(delivery.totalWeight),
        TextCellValue(
          recorderDisplayName(delivery.recordedByUserId, recorderNames),
        ),
        for (var index = 0; index < maxBags; index++) ...[
          if (index < delivery.bagWeights.length)
            DoubleCellValue(delivery.bagWeights[index])
          else
            TextCellValue(''),
          if (index < delivery.bagWeights.length)
            TextCellValue(
              recorderDisplayName(
                delivery.recorderForBag(index),
                recorderNames,
              ),
            )
          else
            TextCellValue(''),
        ],
      ]);
    }
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel workbook could not be encoded');
    }
    final directory = await _directoryProvider();
    try {
      final file = File(path.join(directory.path, filename));
      return await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StateError('Excel file could not be written: ${error.message}');
    }
  }

  Future<File> _writeStatement(
    String filename,
    SupplierStatement statement,
  ) async {
    final recorderNames = await recorderNamesProvider?.call() ?? const {};
    final workbook = Excel.createExcel();
    final sheet = workbook['Statement'];
    sheet.appendRow([
      TextCellValue('Supplier'),
      TextCellValue(statement.supplier.name),
    ]);
    sheet.appendRow([
      TextCellValue('From'),
      TextCellValue(_datePart(statement.from)),
    ]);
    sheet.appendRow([
      TextCellValue('To'),
      TextCellValue(_datePart(statement.to)),
    ]);
    sheet.appendRow(const []);
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Product'),
      TextCellValue('Number of Bags'),
      TextCellValue('Total Weight'),
      TextCellValue('Recorded By'),
    ]);
    for (final delivery in statement.deliveries) {
      sheet.appendRow([
        TextCellValue(_datePart(delivery.recordedAt)),
        TextCellValue(delivery.product.name),
        IntCellValue(delivery.numberOfBags),
        DoubleCellValue(delivery.totalWeight),
        TextCellValue(
          recorderDisplayName(delivery.recordedByUserId, recorderNames),
        ),
      ]);
    }
    sheet.appendRow(const []);
    sheet.appendRow([
      TextCellValue('TOTAL BAGS'),
      IntCellValue(statement.totalBags),
    ]);
    sheet.appendRow([
      TextCellValue('TOTAL WEIGHT'),
      DoubleCellValue(statement.totalWeight),
    ]);
    return _saveWorkbook(filename, workbook);
  }

  Future<File> _saveWorkbook(String filename, Excel workbook) async {
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Excel workbook could not be encoded');
    }
    final directory = await _directoryProvider();
    try {
      final file = File(path.join(directory.path, filename));
      return await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StateError('Excel file could not be written: ${error.message}');
    }
  }

  static String _datePart(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _safeName(String value) =>
      value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');

  static Future<Directory> _defaultDirectory() async =>
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
}
