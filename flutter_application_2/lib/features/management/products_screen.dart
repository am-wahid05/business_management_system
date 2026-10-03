import 'package:flutter/material.dart';

import '../../domain/models/product.dart';
import '../products/product_form_screen.dart';
import '../products/product_repository.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({required this.repository, super.key});

  final ProductRepository repository;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _products;
  bool _showInactive = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _products = widget.repository.all(activeOnly: !_showInactive);
  }

  Future<void> _addProduct() async {
    await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => ProductFormScreen(repository: widget.repository)));
    setState(_reload);
  }

  Future<void> _toggle(Product product) async {
    await widget.repository.setActive(product, !product.isActive);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addProduct, icon: const Icon(Icons.add), label: const Text('Add product')),
      body: FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Could not load products: ${snapshot.error}'));
          final products = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text('Product catalogue', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text('Products are stored in the local SQLite database.'),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(title: const Text('Show inactive products'), value: _showInactive, onChanged: (value) => setState(() { _showInactive = value; _reload(); })),
              const SizedBox(height: 8),
              if (products.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No products found.'))),
              ...products.map((product) => Card(
                    child: ListTile(
                      leading: Icon(product.isActive ? Icons.inventory_2_outlined : Icons.inventory_2),
                      title: Text(product.name),
                      subtitle: Text('${product.id} · ${product.isActive ? 'Active' : 'Inactive'}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            await Navigator.push<Product>(context, MaterialPageRoute(builder: (_) => ProductFormScreen(repository: widget.repository, product: product)));
                            setState(_reload);
                          } else {
                            await _toggle(product);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'toggle', child: Text(product.isActive ? 'Deactivate' : 'Activate')),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
