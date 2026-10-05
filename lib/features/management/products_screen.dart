import 'package:flutter/material.dart';

import '../../app/app_navigation.dart';
import '../../app/app_responsive.dart';
import '../../app/app_ui.dart';
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
    await Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(repository: widget.repository),
      ),
    );
    setState(_reload);
  }

  Future<void> _toggle(Product product) async {
    await widget.repository.setActive(product, !product.isActive);
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      drawer: adminDrawerFor(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addProduct,
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
      ),
      body: FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return AppResponsive(
              centre: false,
              builder: (context, size) => ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  AppSkeleton(width: 220, height: 28),
                  SizedBox(height: 12),
                  AppSkeleton(width: 360, height: 16),
                  SizedBox(height: 24),
                  AppLoadingList(rows: 6),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return AppResponsive(
              centre: false,
              builder: (context, size) => AppErrorState(
                title: 'Products unavailable',
                message: 'We could not load the product catalogue.',
                onRetry: () => setState(_reload),
              ),
            );
          }
          final products = snapshot.data!;
          return AppResponsive(
            maxWidth: AppBreakpoints.contentMaxWidth,
            centre: false,
            builder: (context, size) => ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                AppPageHeader(
                  title: 'Product catalogue',
                  subtitle:
                      'The commodities your company receives and records '
                      'deliveries against.',
                  // A filter chip rather than a SwitchListTile: a switch tile
                  // carries a tall minimum width, so inside a page header it
                  // either overflows a narrow header or renders as a slab.
                  action: FilterChip(
                    label: const Text('Show inactive'),
                    avatar: const Icon(Icons.visibility_off_outlined, size: 17),
                    selected: _showInactive,
                    onSelected: (value) => setState(() {
                      _showInactive = value;
                      _reload();
                    }),
                  ),
                ),
                const SizedBox(height: 18),
                if (products.isEmpty)
                  AppEmptyState(
                    title: 'No products yet',
                    message:
                        'Add the agricultural products your company receives.',
                    icon: Icons.inventory_2_outlined,
                    action: OutlinedButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Add product'),
                    ),
                  )
                else
                  AppPanel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < products.length;
                          index++
                        ) ...[
                          _ProductRow(
                            product: products[index],
                            onEdit: () => _edit(products[index]),
                            onToggle: () => _toggle(products[index]),
                          ),
                          if (index != products.length - 1)
                            const Divider(height: 1),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _edit(Product product) async {
    await Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ProductFormScreen(repository: widget.repository, product: product),
      ),
    );
    setState(_reload);
  }
}

/// One product row.
///
/// A dedicated row rather than a [Card] per product: a card per row makes a long
/// catalogue read as a stack of unrelated boxes instead of one table.
class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.onEdit,
    required this.onToggle,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: product.isActive
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 20,
              color: product.isActive
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  product.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!product.isActive)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: AppStatusPill(
                label: 'Inactive',
                icon: Icons.pause_circle_outline,
                color: scheme.onSurfaceVariant,
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Product actions',
            onSelected: (action) => action == 'edit' ? onEdit() : onToggle(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(
                value: 'toggle',
                child: Text(product.isActive ? 'Deactivate' : 'Activate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
