import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'product_screens.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final _query = TextEditingController();
  String? _category;
  bool _lowOnly = false;
  bool _inactiveOnly = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    return Scaffold(
      appBar: KiranaBar(title: tr('stock')),
      floatingActionButton: manager
          ? Builder(
              builder: (context) => FloatingActionButton.extended(
                key: const Key('stock_add_product'),
                icon: const Icon(Icons.add),
                label: Text(tr('add_product')),
                onPressed: () => push(context, const ProductFormScreen()),
              ),
            )
          : null,
      body: Live<List<Product>>(
        id: manager,
        stream: (repo) => repo.products(includeInactive: manager),
        builder: (context, products) {
          final q = _query.text.trim().toLowerCase();
          final categories =
              products
                  .map((p) => p.category.trim())
                  .where((c) => c.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();
          final list = products.where((p) {
            if (p.active == _inactiveOnly) return false;
            if (_category != null && p.category != _category) return false;
            if (_lowOnly && !(p.isLowStock || p.stockMilli < 0)) return false;
            return q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                p.nameTe.toLowerCase().contains(q) ||
                p.barcode.contains(q);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  key: const Key('stock_search'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: tr('billing_search_hint'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: const Key('stock_low_filter'),
                        label: Text(tr('low_stock')),
                        selected: _lowOnly,
                        onSelected: (v) => setState(() => _lowOnly = v),
                      ),
                    ),
                    if (manager)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          key: const Key('stock_inactive_filter'),
                          label: Text(tr('inactive')),
                          selected: _inactiveOnly,
                          onSelected: (v) => setState(() => _inactiveOnly = v),
                        ),
                      ),
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (on) =>
                              setState(() => _category = on ? c : null),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.inventory_2_outlined,
                        message: products.isEmpty
                            ? tr('no_products')
                            : tr('no_matches'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = list[i];
                          return _StockRow(
                            product: p,
                            tr: tr,
                            language: language,
                            onTap: () => push(
                              context,
                              ProductDetailScreen(productId: p.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.product,
    required this.tr,
    required this.language,
    required this.onTap,
  });

  final Product product;
  final Tr tr;
  final String language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final negative = product.stockMilli < 0;
    final color = negative
        ? KiranaColors.dues
        : product.isLowStock
        ? KiranaColors.warning
        : null;
    return ListTile(
      key: ValueKey('stock_${product.id}'),
      minTileHeight: 64,
      title: Text(
        product.displayName(language),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '${formatRupees(product.pricePaise)} / ${unitLabel(tr, product.unit)}',
          ),
          if (product.category.isNotEmpty) Text(product.category),
          if (negative) Flag(tr('negative_stock'), color: KiranaColors.dues),
          if (!negative && product.isLowStock)
            Flag(tr('low_stock'), color: KiranaColors.warning),
        ],
      ),
      trailing: Text(
        formatQuantity(product.stockMilli),
        style: theme.textTheme.titleLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: onTap,
    );
  }
}
