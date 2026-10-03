import 'package:flutter/material.dart';

import '../../domain/models/product.dart';
import 'product_repository.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({required this.repository, this.product, super.key});

  final ProductRepository repository;
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final TextEditingController _nameController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final product = widget.product;
      final saved = product == null
          ? await widget.repository.create(_nameController.text)
          : await widget.repository.update(product.copyWith(name: _nameController.text));
      if (mounted) Navigator.pop(context, saved);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit Product' : 'Add Product')),
      body: Form(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_error != null) const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Product name *'),
              textCapitalization: TextCapitalization.words,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(editing ? 'Save Changes' : 'Add Product')),
          ],
        ),
      ),
    );
  }
}
