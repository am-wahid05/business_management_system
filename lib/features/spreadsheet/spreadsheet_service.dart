import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../imports/import_header_detector.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receiving_service.dart';
import 'spreadsheet_row.dart';
import 'spreadsheet_validation.dart';

/// Loads, validates and saves spreadsheet rows.
///
/// Every write goes through the existing [DeliveryRepository] and
/// [ReceivingService], so company isolation, duplicate protection and
/// recorded-by attribution follow the same rules the rest of the application
/// already enforces. Nothing here talks to Supabase directly.
class SpreadsheetService {
  SpreadsheetService({
    required this.deliveryRepository,
    required this.receivingService,
    this.recorderNamesProvider,
    this.catalogueProvider,
    this.userIdProvider,
  });

  final DeliveryRepository deliveryRepository;

  /// Used for new rows so supplier matching, company scoping and recorder
  /// attribution are applied exactly as they are on the receiving screen.
  final ReceivingService receivingService;

  /// Maps a recorder id to a display name, for the "Recorded By" column.
  final Future<Map<String, String>> Function()? recorderNamesProvider;

  /// The company's products, so a row without a product id can resolve one.
  final Future<List<Product>> Function()? catalogueProvider;

  final String? Function()? userIdProvider;

  Future<List<Product>> _catalogue() async =>
      await catalogueProvider?.call() ?? Product.initialProducts;

  /// Loads the existing deliveries for a date range into editable rows.
  ///
  /// The range is passed to the repository, which already restricts the result
  /// to the active company.
  Future<List<SpreadsheetRow>> load({
    required DateTime from,
    required DateTime to,
  }) async {
    final deliveries = await deliveryRepository.forRange(from, to);
    final names =
        await recorderNamesProvider?.call() ?? const <String, String>{};
    return deliveries
        .map(
          (delivery) => SpreadsheetRow.fromDelivery(
            delivery,
            recorderName: recorderDisplayName(delivery.recordedByUserId, names),
          ),
        )
        .toList(growable: false);
  }

  /// Saves the changed rows and reports what happened.
  ///
  /// Unchanged rows are never written, so opening and saving the grid cannot
  /// silently overwrite a record.
  Future<SpreadsheetSaveResult> save(List<SpreadsheetRow> rows) async {
    var created = 0;
    var updated = 0;
    var unchanged = 0;
    var skippedDuplicates = 0;
    var failed = 0;
    var suppliersCreated = 0;
    final errors = <String>[];

    for (final row in rows) {
      if (row.isRemoved) continue;
      final check = applyRowValidation(row);
      if (!check.isValid) {
        failed++;
        errors.add('${row.deliveryId ?? 'New row'}: ${row.error}');
        continue;
      }
      try {
        if (row.isNew) {
          // A row with no supplier id makes the receiving service look the
          // supplier up by name, which may create a new profile.
          final neededNewSupplier = row.supplierId.isEmpty;
          final saved = await _createRow(row);
          if (saved == null) {
            skippedDuplicates++;
            row.error = 'Looks like a duplicate of an existing record';
          } else {
            created++;
            if (neededNewSupplier) suppliersCreated++;
            _adoptSaved(row, saved);
          }
        } else if (row.state == SpreadsheetRowState.edited) {
          await _updateRow(row);
          updated++;
        } else {
          unchanged++;
        }
      } on Object catch (error) {
        failed++;
        final message = error.toString();
        row.error = message;
        errors.add('${row.deliveryId ?? 'New row'}: $message');
      }
    }

    return SpreadsheetSaveResult(
      created: created,
      updated: updated,
      unchanged: unchanged,
      skippedDuplicates: skippedDuplicates,
      failed: failed,
      suppliersCreated: suppliersCreated,
      errors: errors,
    );
  }

  /// Saves a new row through the receiving service, which performs supplier
  /// matching, company scoping and recorder attribution.
  ///
  /// Returns null when the row looks like a record that already exists, so the
  /// existing duplicate protection is preserved.
  Future<Delivery?> _createRow(SpreadsheetRow row) async {
    final recordedAt = row.recordedAt!;
    final catalogue = await _catalogue();
    final productId =
        row.productId ??
        inferProductId(row.productName, catalogue) ??
        row.productName;

    if (await deliveryRepository.hasLikelyDuplicate(
      recordedAt: recordedAt,
      supplierId: row.supplierId,
      supplierName: row.supplierName,
      productId: productId,
      totalWeight: row.totalWeight!,
    )) {
      return null;
    }

    // A bulk row stores the scale total and the bag count and has NO bag
    // weights, so none are ever derived from the total.
    final isBulk = row.recordType == DeliveryRecordType.bulk;
    final delivery = Delivery(
      id:
          'sheet-${DateTime.now().microsecondsSinceEpoch}-'
          '${row.supplierName.hashCode.abs()}',
      supplier: Supplier(
        id: row.supplierId,
        name: row.supplierName,
        type: SupplierType.farmer,
        town: '',
        district: '',
        region: '',
      ),
      product: Product(id: productId, name: row.productName),
      recordedAt: recordedAt,
      bagWeights: isBulk ? const <double>[] : row.parsedWeights!,
      recordedByUserId: userIdProvider?.call(),
      recordType: isBulk
          ? DeliveryRecordType.bulk
          : DeliveryRecordType.individual,
      bulkTotalWeight: isBulk ? row.totalWeight : null,
      bulkBagCount: isBulk ? row.bagCount : null,
      notes: row.notes,
    );

    return receivingService.saveDelivery(
      supplierId: row.supplierId.isEmpty ? null : row.supplierId,
      supplierName: row.supplierName,
      supplierType: SupplierType.farmer,
      town: '',
      district: '',
      region: '',
      delivery: delivery,
    );
  }

  /// Saves an edited existing row.
  ///
  /// Only the bag weights are writable in the current model, so an edited row
  /// is written through the repository's weight update, which keeps the
  /// original recorder, marks the record as corrected and queues it for sync.
  Future<void> _updateRow(SpreadsheetRow row) async {
    final saved = await deliveryRepository.updateWeights(
      row.deliveryId!,
      row.parsedWeights!,
    );
    _adoptSaved(row, saved);
  }

  /// Copies back the values the database decided, so the grid shows the
  /// supplier that was matched and the status that was actually stored.
  void _adoptSaved(SpreadsheetRow row, Delivery saved) {
    // The saved id is adopted so the row stops being "new". Without it the grid
    // would try to create the same delivery again on the next save.
    row.deliveryId = saved.id;
    row.recordType = saved.recordType;
    row.bagCount = saved.numberOfBags;
    if (saved.isBulk) {
      row.bulkTotalWeight = saved.totalWeight;
      row.notes = saved.notes;
    }
    row.supplierId = saved.supplier.id;
    row.supplierName = saved.supplier.name;
    row.productId = saved.product.id;
    row.productName = saved.product.name;
    row.weights = saved.isBulk
        ? SpreadsheetRow.bulkWeightsMarker
        : formatWeights(saved.bagWeights);
    row.status = saved.status.name;
    row.state = SpreadsheetRowState.unchanged;
    row.error = null;
  }
}
