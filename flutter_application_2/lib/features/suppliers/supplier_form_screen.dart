import 'package:flutter/material.dart';

import '../../domain/models/supplier.dart';
import 'supplier_repository.dart';
import '../locations/ghana_location_fields.dart';

class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({required this.repository, this.supplier, super.key});

  final SupplierRepository repository;
  final Supplier? supplier;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _townController;
  late final TextEditingController _districtController;
  late final TextEditingController _regionController;
  late final TextEditingController _notesController;
  late SupplierType _type;
  String? _errorMessage;

  bool get isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _nameController = TextEditingController(text: supplier?.name);
    _phoneController = TextEditingController(text: supplier?.phone);
    _townController = TextEditingController(text: supplier?.town);
    _districtController = TextEditingController(text: supplier?.district);
    _regionController = TextEditingController(text: supplier?.region);
    _notesController = TextEditingController(text: supplier?.notes);
    _type = supplier?.type ?? SupplierType.farmer;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _townController.dispose();
    _districtController.dispose();
    _regionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    try {
      final supplier = widget.supplier;
      final saved = supplier == null
          ? widget.repository.create(
              name: _nameController.text,
              type: _type,
              phone: _phoneController.text,
              town: _townController.text,
              district: _districtController.text,
              region: _regionController.text,
              notes: _notesController.text,
            )
          : widget.repository.update(
              supplier.copyWith(
                name: _nameController.text.trim(),
                type: _type,
                phone: _phoneController.text.trim(),
                town: _townController.text.trim(),
                district: _districtController.text.trim(),
                region: _regionController.text.trim(),
                notes: _notesController.text.trim(),
              ),
            );
      if (mounted) Navigator.pop(context, saved);
    } on StateError catch (error) {
      setState(() => _errorMessage = error.message);
    } on ArgumentError catch (error) {
      setState(() => _errorMessage = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Supplier' : 'Create Supplier')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Full name *'),
              validator: _required,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SupplierType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Supplier type *'),
              items: SupplierType.values
                  .map((type) => DropdownMenuItem(value: type, child: Text(_typeLabel(type))))
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 16),
            TextFormField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone (optional)'), keyboardType: TextInputType.phone),
            const SizedBox(height: 16),
            GhanaLocationFields(regionController: _regionController, districtController: _districtController, townController: _townController, onChanged: () => setState(() {})),
            const SizedBox(height: 16),
            TextFormField(controller: _notesController, decoration: const InputDecoration(labelText: 'Notes (optional)'), maxLines: 3),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(isEditing ? 'Save Changes' : 'Create Supplier')),
          ],
        ),
      ),
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;

  static String _typeLabel(SupplierType type) => type == SupplierType.farmer ? 'Farmer' : 'Aggregator';
}
