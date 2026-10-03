import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/models/delivery.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../products/product_repository.dart';
import '../receiving/delivery_repository.dart';
import '../receiving/receiving_service.dart';
import '../suppliers/supplier_repository.dart';
import '../locations/ghana_location_fields.dart';

class NewReceivingScreen extends StatefulWidget {
  const NewReceivingScreen({
    required this.repository,
    required this.productRepository,
    required this.deliveryRepository,
    required this.receivingService,
    super.key,
  });

  final SupplierRepository repository;
  final ProductRepository productRepository;
  final DeliveryRepository deliveryRepository;
  final ReceivingService receivingService;

  @override
  State<NewReceivingScreen> createState() => _NewReceivingScreenState();
}

class _NewReceivingScreenState extends State<NewReceivingScreen> {
  static const _bagsPerRow = 10;
  static const _bagsPerSheet = 30;

  final _searchController = TextEditingController();
  final _weightControllers = <TextEditingController>[
    ...List.generate(_bagsPerSheet, (_) => TextEditingController()),
  ];
  Supplier? _selectedSupplier;
  Product? _selectedProduct;
  SupplierType _supplierType = SupplierType.farmer;
  final _townController = TextEditingController();
  final _districtController = TextEditingController();
  final _regionController = TextEditingController();
  final _phoneController = TextEditingController();
  late Future<List<Product>> _products;
  DateTime _recordedDate = DateTime.now();
  String? _errorMessage;
  bool _isSaving = false;

  List<Supplier> get _matches => widget.repository
      .search(_searchController.text)
      .where((supplier) => supplier.isActive)
      .toList();

  double get _totalWeight => _weightControllers.fold(
    0,
    (total, controller) =>
        total + (double.tryParse(controller.text.trim()) ?? 0),
  );

  @override
  void initState() {
    super.initState();
    _products = widget.productRepository.all(activeOnly: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _townController.dispose();
    _districtController.dispose();
    _regionController.dispose();
    _phoneController.dispose();
    for (final controller in _weightControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addSheet() {
    setState(() {
      _weightControllers.addAll(
        List.generate(_bagsPerSheet, (_) => TextEditingController()),
      );
    });
  }

  bool get _canAddSheet =>
      _weightControllers.length >= _bagsPerSheet &&
      _weightControllers.every((controller) {
        final weight = double.tryParse(controller.text.trim());
        return weight != null && weight.isFinite && weight > 0;
      });

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: _recordedDate,
    );
    if (selected != null) setState(() => _recordedDate = selected);
  }

  Future<void> _saveDelivery() async {
    final weights = <double>[];
    for (final controller in _weightControllers) {
      final text = controller.text.trim();
      if (text.isEmpty) {
        setState(() => _errorMessage = 'Every bag must have a weight.');
        return;
      }
      final weight = double.tryParse(text);
      if (weight == null || !weight.isFinite || weight <= 0) {
        setState(
          () =>
              _errorMessage = 'Bag weights must be numbers greater than zero.',
        );
        return;
      }
      weights.add(weight);
    }
    if (_searchController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Select a supplier before saving.');
      return;
    }
    if (_selectedProduct == null) {
      setState(() => _errorMessage = 'Select a product before saving.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSaving = true;
    });
    try {
      final now = DateTime.now();
      final supplier =
          _selectedSupplier ??
          Supplier(
            internalId: 'draft',
            id: 'draft',
            name: _searchController.text.trim(),
            type: _supplierType,
            town: _townController.text.trim(),
            district: _districtController.text.trim(),
            region: _regionController.text.trim(),
          );
      final delivery = Delivery(
        id: _newDeliveryId(),
        supplier: supplier,
        product: _selectedProduct!,
        recordedAt: DateTime(
          _recordedDate.year,
          _recordedDate.month,
          _recordedDate.day,
          now.hour,
          now.minute,
          now.second,
        ),
        bagWeights: weights,
        recordedByUserId: widget.receivingService.currentUserId,
        synchronizationStatus: SynchronizationStatus.pendingSync,
      );
      final saved = await widget.receivingService.saveDelivery(
        supplierName: _searchController.text,
        supplierType: _supplierType,
        town: _townController.text,
        district: _districtController.text,
        region: _regionController.text,
        phone: _phoneController.text,
        selectedSupplier: _selectedSupplier,
        delivery: delivery,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery saved offline.')),
        );
        Navigator.pop(context, saved);
      }
    } catch (error) {
      if (mounted)
        setState(() => _errorMessage = 'Could not save delivery: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _newDeliveryId() {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return 'delivery-${DateTime.now().microsecondsSinceEpoch}-$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Scaffold(
      appBar: AppBar(title: const Text('New Receiving')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
          children: [
            Text(
              'Record delivery',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            _sectionTitle(context, 'Supplier'),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() => _selectedSupplier = null),
              decoration: const InputDecoration(
                labelText: 'Search supplier name, ID, phone, or town',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (_searchController.text.trim().isNotEmpty &&
                _selectedSupplier == null)
              ...matches.map(
                (supplier) => Card(
                  child: ListTile(
                    minVerticalPadding: 12,
                    title: Text(supplier.name),
                    subtitle: Text(
                      '${supplier.id} · ${supplier.type == SupplierType.farmer ? 'Farmer' : 'Aggregator'} · ${supplier.town}',
                    ),
                    onTap: () => setState(() {
                      _selectedSupplier = supplier;
                      _searchController.text = supplier.name;
                    }),
                  ),
                ),
              ),
            if (_searchController.text.trim().isNotEmpty &&
                matches.isEmpty &&
                _selectedSupplier == null) ...[
              const Card(
                child: ListTile(
                  minVerticalPadding: 12,
                  leading: Icon(Icons.person_add_alt_1),
                  title: Text('No existing supplier found'),
                  subtitle: Text(
                    'A supplier profile will be created when this delivery is saved.',
                  ),
                ),
              ),
              DropdownButtonFormField<SupplierType>(
                initialValue: _supplierType,
                decoration: const InputDecoration(labelText: 'Supplier type'),
                items: SupplierType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(
                          type == SupplierType.farmer ? 'Farmer' : 'Aggregator',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _supplierType = value);
                },
              ),
              const SizedBox(height: 12),
              GhanaLocationFields(
                regionController: _regionController,
                districtController: _districtController,
                townController: _townController,
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
            if (_selectedSupplier != null)
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: ListTile(
                  minVerticalPadding: 12,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(_selectedSupplier!.name),
                  subtitle: Text(
                    '${_selectedSupplier!.id} · ${_selectedSupplier!.town}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _selectedSupplier = null),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Product and date'),
            const SizedBox(height: 8),
            FutureBuilder<List<Product>>(
              future: _products,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done)
                  return const LinearProgressIndicator();
                if (snapshot.hasError)
                  return Text('Could not load products: ${snapshot.error}');
                return DropdownButtonFormField<Product>(
                  initialValue: _selectedProduct,
                  decoration: const InputDecoration(
                    labelText: 'Active product',
                  ),
                  items: snapshot.data!
                      .map(
                        (product) => DropdownMenuItem(
                          value: product,
                          child: Text(product.name),
                        ),
                      )
                      .toList(),
                  onChanged: (product) =>
                      setState(() => _selectedProduct = product),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _chooseDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text('Date: ${_formatDate(_recordedDate)}'),
            ),
            const SizedBox(height: 24),
            _sectionTitle(context, 'Bag weights'),
            const SizedBox(height: 8),
            _buildWeightTable(context),
            if (_canAddSheet) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _addSheet,
                icon: const Icon(Icons.add),
                label: const Text('Add another sheet'),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bags',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_weightControllers.length}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Total weight',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${_totalWeight.toStringAsFixed(1)} kg',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveDelivery,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save Delivery'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionTitle(BuildContext context, String title) =>
      Text(title, style: Theme.of(context).textTheme.titleLarge);

  Widget _buildWeightTable(BuildContext context) {
    final cells = <Widget>[
      ...List.generate(
        _bagsPerRow,
        (index) => _tableCell(
          Text(
            'Bag ${index + 1}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ),
      _tableCell(
        Text('Row total', style: Theme.of(context).textTheme.labelSmall),
      ),
    ];
    final rows = <TableRow>[TableRow(children: cells)];
    for (
      var start = 0;
      start < _weightControllers.length;
      start += _bagsPerRow
    ) {
      final end = start + _bagsPerRow;
      final controllers = _weightControllers.sublist(start, end);
      final rowTotal = controllers.fold<double>(
        0,
        (total, controller) =>
            total + (double.tryParse(controller.text.trim()) ?? 0),
      );
      rows.add(
        TableRow(
          children: [
            ...controllers.map(
              (controller) => _tableCell(
                SizedBox(
                  width: 72,
                  child: TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(isDense: true),
                  ),
                ),
              ),
            ),
            _tableCell(
              Text(
                '${rowTotal.toStringAsFixed(1)} kg',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
    rows.add(
      TableRow(
        children: [
          _tableCell(const Text('Full total', textAlign: TextAlign.center)),
          ...List.generate(
            _bagsPerRow - 1,
            (_) => _tableCell(const SizedBox.shrink()),
          ),
          _tableCell(
            Text(
              '${_totalWeight.toStringAsFixed(1)} kg',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const FixedColumnWidth(78),
        border: TableBorder.all(color: Theme.of(context).dividerColor),
        children: rows,
      ),
    );
  }

  Widget _tableCell(Widget child) => Padding(
    padding: const EdgeInsets.all(4),
    child: Center(child: child),
  );

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
