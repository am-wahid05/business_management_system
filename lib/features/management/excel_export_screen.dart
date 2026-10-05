import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../app/app_navigation.dart';
import '../../app/app_routes.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../exports/excel_export_service.dart';
import '../products/product_repository.dart';
import '../suppliers/supplier_repository.dart';

/// Lets the Admin pick one or more suppliers for an export.
///
/// Search is delegated to [SupplierRepository.search], which already matches on
/// name, supplier id and phone. Reusing it means the export picker filters
/// exactly the way the rest of the app does, and because that repository only
/// ever holds the active company's suppliers, a search here can never surface
/// another company's data.
class SupplierPickerDialog extends StatefulWidget {
  const SupplierPickerDialog({required this.repository, super.key});

  final SupplierRepository repository;

  /// Shows the picker and returns the selected suppliers.
  ///
  /// Returns null when the Admin cancels, so the caller can tell a cancel apart
  /// from an empty selection and do nothing in that case.
  static Future<List<Supplier>?> show(
    BuildContext context,
    SupplierRepository repository,
  ) {
    return showDialog<List<Supplier>>(
      context: context,
      builder: (context) => SupplierPickerDialog(repository: repository),
    );
  }

  @override
  State<SupplierPickerDialog> createState() => _SupplierPickerDialogState();
}

class _SupplierPickerDialogState extends State<SupplierPickerDialog> {
  final _searchController = TextEditingController();
  final _selected = <String, Supplier>{};
  List<Supplier> _results = const [];

  @override
  void initState() {
    super.initState();
    _results = widget.repository.suppliers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filters through the repository so name, ID and contact all match.
  void _runSearch(String query) {
    setState(() => _results = widget.repository.search(query));
  }

  void _toggle(Supplier supplier) {
    setState(() {
      if (_selected.containsKey(supplier.id)) {
        _selected.remove(supplier.id);
      } else {
        _selected[supplier.id] = supplier;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Select suppliers'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _runSearch,
              decoration: const InputDecoration(
                labelText: 'Search by name, supplier ID or contact',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchController.text.trim().isEmpty
                            ? 'No suppliers in this company yet.'
                            : 'No supplier matches this search.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final supplier = _results[index];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.containsKey(supplier.id),
                          onChanged: (_) => _toggle(supplier),
                          title: Text(supplier.name),
                          // Both the id and the contact are shown, because the
                          // Admin may have searched by either and needs to be
                          // able to confirm they picked the right supplier.
                          subtitle: Text(
                            '${supplier.id}   ·   ${supplier.phone ?? 'No contact'}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.values.toList()),
          child: Text('Select ${_selected.length}'),
        ),
      ],
    );
  }
}

/// Lets the Admin pick one or more products for an export.
///
/// Products come from [ProductRepository.all], which is scoped to the active
/// company, so the picker can only ever offer that company's products.
class ProductPickerDialog extends StatefulWidget {
  const ProductPickerDialog({required this.products, super.key});

  final List<Product> products;

  static Future<List<Product>?> show(
    BuildContext context,
    List<Product> products,
  ) {
    return showDialog<List<Product>>(
      context: context,
      builder: (context) => ProductPickerDialog(products: products),
    );
  }

  @override
  State<ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<ProductPickerDialog> {
  final _searchController = TextEditingController();
  final _selected = <String, Product>{};

  List<Product> get _results {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.products;
    return widget.products
        .where(
          (product) =>
              product.name.toLowerCase().contains(query) ||
              product.id.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(Product product) {
    setState(() {
      if (_selected.containsKey(product.id)) {
        _selected.remove(product.id);
      } else {
        _selected[product.id] = product;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AlertDialog(
      title: const Text('Select products'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              // Rebuilds on every keystroke; the list is small and already
              // in memory, so filtering here avoids another database read.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search by product name or ID',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        widget.products.isEmpty
                            ? 'This company has no products yet.'
                            : 'No product matches this search.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final product = results[index];
                        return CheckboxListTile(
                          dense: true,
                          value: _selected.containsKey(product.id),
                          onChanged: (_) => _toggle(product),
                          title: Text(product.name),
                          subtitle: Text(product.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.values.toList()),
          child: Text('Select ${_selected.length}'),
        ),
      ],
    );
  }
}

class ExcelExportScreen extends StatefulWidget {
  const ExcelExportScreen({
    required this.service,
    this.supplierRepository,
    this.productRepository,
    super.key,
  });

  final ExcelExportService service;

  /// Used only to list and search suppliers for the picker. When it is absent
  /// the picker-based export is hidden rather than shown as a control that
  /// cannot work.
  final SupplierRepository? supplierRepository;

  /// Used only to list the active company's products for the picker.
  final ProductRepository? productRepository;

  @override
  State<ExcelExportScreen> createState() => _ExcelExportScreenState();
}

class _ExcelExportScreenState extends State<ExcelExportScreen> {
  final _selectedIds = TextEditingController();
  DateTime _date = DateTime.now();

  /// The inclusive range used by the range-based exports.
  ///
  /// Defaults to the start and end of the current month, which is the most
  /// common ask and means the screen is immediately usable.
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _to = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
  ).subtract(const Duration(days: 1));
  List<Supplier> _chosenSuppliers = const [];
  List<Product> _chosenProducts = const [];
  List<Product> _availableProducts = const [];
  bool _working = false;
  String? _message;
  bool _messageIsError = false;

  /// Loads the active company's products for the picker.
  Future<void> _loadProducts() async {
    final repository = widget.productRepository;
    if (repository == null) {
      if (mounted) setState(() => _availableProducts = const []);
      return;
    }
    final products = await repository.all();
    if (!mounted) return;
    setState(() => _availableProducts = products);
  }

  bool get _canPickProducts => widget.productRepository != null;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didUpdateWidget(ExcelExportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A company switch can hand this screen a different repository, so the
    // product list is refreshed rather than kept from the previous company.
    if (oldWidget.productRepository != widget.productRepository) {
      _chosenProducts = const [];
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _selectedIds.dispose();
    super.dispose();
  }

  /// Asks the Admin where to save, then runs [action].
  ///
  /// The destination is chosen first so the export never writes anywhere the
  /// Admin did not pick. Cancelling the dialog returns normally without running
  /// the export and without showing an error, because nothing failed.
  Future<void> _export(
    Future<dynamic> Function() action, {
    required String suggestedName,
  }) async {
    final directory = await _chooseDestination(suggestedName);
    // null means the Admin cancelled the dialog.
    if (directory == null) return;
    widget.service.destinationPath = directory;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final file = await action();
      if (!mounted) return;
      setState(() {
        _messageIsError = false;
        _message = 'Excel file exported successfully.\n${file.path}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _messageIsError = true;
        _message = 'Export failed: $error';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Opens the platform save dialog and returns the chosen directory.
  ///
  /// Returns null when the Admin cancels. The chosen file name is only a
  /// default; the user is free to change it, and the service always applies the
  /// filename it generated for the export so the workbook is never written with
  /// a name that does not match its contents.
  Future<String?> _chooseDestination(String suggestedName) async {
    final directory = widget.service.destinationPath;
    try {
      final chosen = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Excel file',
        fileName: suggestedName,
        initialDirectory: directory,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        lockParentWindow: true,
      );
      if (chosen == null) return null;
      // The dialog returns a full file path; exports write their own generated
      // name into the folder that path belongs to.
      return path.dirname(chosen);
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _messageIsError = true;
        _message =
            'Could not open the save dialog, so the file was not written.\n$error';
      });
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Excel Export'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: shellDrawerFor(context),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Export database records',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Excel files are generated from SQLite and saved outside the database.',
          ),
          const SizedBox(height: 12),
          _compactButton(
            context,
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, AppRoutes.excelImport),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import historical Excel records'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'All records'),
          const SizedBox(height: 8),
          // The date range applies to the record date, not to when the export
          // runs, and both ends are included.
          _dateRangeFields(),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: _working ? null : _chooseAllDates,
                child: const Text('All dates'),
              ),
              TextButton(
                onPressed: _working ? null : _chooseCurrentMonth,
                child: const Text('This month'),
              ),
              TextButton(
                onPressed: _working ? null : _choosePreviousMonth,
                child: const Text('Last month'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _compactButton(
            context,
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () => _export(
                      () => widget.service.exportRange(_from, _to),
                      suggestedName: widget.service.suggestFileName(
                        'Records',
                        _from,
                        _to,
                      ),
                    ),
              icon: const Icon(Icons.table_view_outlined),
              label: const Text('Export all records'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Daily report'),
          const SizedBox(height: 8),
          _compactButton(
            context,
            OutlinedButton.icon(
              onPressed: _working ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text('Daily report: ${_formatDate(_date)}'),
            ),
          ),
          const SizedBox(height: 8),
          _compactButton(
            context,
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () => _export(
                      () => widget.service.exportDaily(_date),
                      suggestedName: widget.service.suggestDailyFileName(_date),
                    ),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Export daily report'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Period reports'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _compactButton(
                  context,
                  FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _export(
                            () => widget.service.exportMonthly(
                              _date.year,
                              _date.month,
                            ),
                            suggestedName: widget.service.suggestFileName(
                              'Monthly_${_date.year}-'
                              '${_date.month.toString().padLeft(2, '0')}',
                              DateTime(_date.year, _date.month),
                              DateTime(
                                _date.year,
                                _date.month + 1,
                              ).subtract(const Duration(days: 1)),
                            ),
                          ),
                    icon: const Icon(Icons.calendar_view_month_outlined),
                    label: const Text('Monthly'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _compactButton(
                  context,
                  FilledButton.icon(
                    onPressed: _working
                        ? null
                        : () => _export(
                            () => widget.service.exportYearly(_date.year),
                            suggestedName: widget.service.suggestFileName(
                              'Yearly',
                              DateTime(_date.year),
                              DateTime(_date.year, 12, 31),
                            ),
                          ),
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: const Text('Yearly'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Supplier records'),
          const SizedBox(height: 8),
          if (widget.supplierRepository == null)
            const Text(
              'Supplier selection needs the company supplier list, which is '
              'not available on this screen.',
            )
          else ...[
            _compactButton(
              context,
              OutlinedButton.icon(
                onPressed: _working ? null : _chooseSuppliers,
                icon: const Icon(Icons.person_search_outlined),
                label: Text(
                  _chosenSuppliers.isEmpty
                      ? 'Select suppliers (search by name, ID or contact)'
                      : 'Selected: ${_chosenSuppliers.map((s) => s.name).join(', ')}',
                ),
              ),
            ),
            if (_chosenSuppliers.length > 1) ...[
              const SizedBox(height: 8),
              _compactButton(
                context,
                TextButton(
                  onPressed: _working
                      ? null
                      : () => setState(() => _chosenSuppliers = const []),
                  child: const Text('Clear selection'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _dateRangeFields(),
            const SizedBox(height: 8),
            _compactButton(
              context,
              FilledButton.icon(
                onPressed: _working || _chosenSuppliers.isEmpty
                    ? null
                    : () => _export(
                        () => _exportChosenSuppliers(),
                        suggestedName: widget.service.suggestFileName(
                          'Suppliers',
                          _from,
                          _to,
                        ),
                      ),
                icon: const Icon(Icons.file_download_outlined),
                label: Text(
                  _chosenSuppliers.length > 1
                      ? 'Export ${_chosenSuppliers.length} suppliers'
                      : 'Export supplier records',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _sectionTitle(context, 'Product records'),
          const SizedBox(height: 8),
          _compactButton(
            context,
            OutlinedButton.icon(
              onPressed: _working || !_canPickProducts ? null : _chooseProducts,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(
                _chosenProducts.isEmpty
                    ? 'Select products (or export all)'
                    : 'Selected: '
                          '${_chosenProducts.map((p) => p.name).join(', ')}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          _dateRangeFields(),
          const SizedBox(height: 8),
          _compactButton(
            context,
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () => _export(
                      () => _exportChosenProducts(),
                      suggestedName: widget.service.suggestFileName(
                        _chosenProducts.length == 1
                            ? 'Product_${_chosenProducts.first.name}'
                            : 'Products',
                        _from,
                        _to,
                      ),
                    ),
              icon: const Icon(Icons.file_download_outlined),
              label: Text(
                _chosenProducts.length > 1
                    ? 'Export ${_chosenProducts.length} products'
                    : 'Export product records',
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'Selected deliveries'),
          const SizedBox(height: 8),
          TextField(
            controller: _selectedIds,
            decoration: const InputDecoration(
              labelText: 'Delivery IDs, separated by commas',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),
          _compactButton(
            context,
            FilledButton.icon(
              onPressed: _working
                  ? null
                  : () => _export(
                      () => widget.service.exportSelected(
                        _selectedIds.text
                            .split(',')
                            .map((id) => id.trim())
                            .where((id) => id.isNotEmpty)
                            .toList(),
                      ),
                      suggestedName: widget.service.suggestFileName(
                        'Selected_Deliveries',
                        _from,
                        _to,
                      ),
                    ),
              icon: const Icon(Icons.checklist_outlined),
              label: const Text('Export selected deliveries'),
            ),
          ),
          if (_working) ...[
            const SizedBox(height: 20),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Preparing Excel file...'),
          ],
          if (_message != null) ...[
            const SizedBox(height: 20),
            SelectableText(
              _message!,
              style: _messageIsError
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _compactButton(BuildContext context, Widget button) =>
      Align(alignment: Alignment.centerLeft, child: button);

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _date,
    );
    if (selected != null) setState(() => _date = selected);
  }

  static Widget _sectionTitle(BuildContext context, String text) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);

  /// Picks one end of the inclusive range.
  ///
  /// The range is kept ordered, so choosing an end date before the start date
  /// swaps them rather than producing an impossible range that would silently
  /// export nothing.
  Future<void> _pickRangeEnd({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (selected == null) return;
    setState(() {
      if (isFrom) {
        _from = selected.isAfter(_to) ? _to : selected;
      } else {
        _to = selected.isBefore(_from) ? _from : selected;
      }
    });
  }

  /// Opens the product picker and remembers what was chosen.
  Future<void> _chooseProducts() async {
    final chosen = await ProductPickerDialog.show(context, _availableProducts);
    // A cancel returns null; leave the previous selection alone.
    if (chosen == null) return;
    setState(() => _chosenProducts = chosen);
  }

  /// Exports the chosen products over the selected range.
  ///
  /// Nothing chosen means "all products", which is what the button label says,
  /// so the common case needs no selection at all.
  Future<dynamic> _exportChosenProducts() {
    if (_chosenProducts.isEmpty) {
      return widget.service.exportRange(_from, _to);
    }
    if (_chosenProducts.length == 1) {
      final product = _chosenProducts.first;
      return widget.service.exportProductsRange([product.id], _from, _to);
    }
    return widget.service.exportProductsRange(
      _chosenProducts.map((product) => product.id).toList(),
      _from,
      _to,
    );
  }

  /// Exports the chosen suppliers over the selected range.
  ///
  /// A single supplier goes through the single-supplier export so its file name
  /// stays readable; several are merged into one workbook that can still be
  /// filtered by the Supplier ID column.
  Future<dynamic> _exportChosenSuppliers() {
    if (_chosenSuppliers.length == 1) {
      final supplier = _chosenSuppliers.first;
      return widget.service.exportSupplierRange(
        supplier.id,
        supplier.name,
        _from,
        _to,
      );
    }
    return widget.service.exportSuppliersRange(
      {for (final supplier in _chosenSuppliers) supplier.id: supplier.name},
      _from,
      _to,
    );
  }

  /// Applies one of the common ranges so the Admin does not have to open two
  /// date pickers for the usual case.
  void _applyPreset(DateTime from, DateTime to) => setState(() {
    _from = from;
    _to = to;
  });

  void _chooseCurrentMonth() {
    final now = DateTime.now();
    _applyPreset(
      DateTime(now.year, now.month),
      DateTime(now.year, now.month + 1).subtract(const Duration(days: 1)),
    );
  }

  void _choosePreviousMonth() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    _applyPreset(
      DateTime(thisMonth.year, thisMonth.month - 1),
      thisMonth.subtract(const Duration(days: 1)),
    );
  }

  void _chooseAllDates() => _applyPreset(DateTime(2000), DateTime(2100));

  /// Opens the supplier picker and remembers what was chosen.
  Future<void> _chooseSuppliers() async {
    final repository = widget.supplierRepository;
    if (repository == null) return;
    final chosen = await SupplierPickerDialog.show(context, repository);
    // A cancel returns null; leave the previous selection alone.
    if (chosen == null) return;
    setState(() => _chosenSuppliers = chosen);
  }

  Widget _dateRangeFields() => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _working ? null : () => _pickRangeEnd(isFrom: true),
          icon: const Icon(Icons.event_outlined),
          label: Text('From: ${_formatDate(_from)}'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: _working ? null : () => _pickRangeEnd(isFrom: false),
          icon: const Icon(Icons.event_outlined),
          label: Text('To: ${_formatDate(_to)}'),
        ),
      ),
    ],
  );

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
