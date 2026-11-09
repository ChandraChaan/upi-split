import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';
import 'products_page.dart';

class ProductDetailPage extends StatelessWidget {
  const ProductDetailPage({super.key, required this.storeId, required this.productId});
  final String storeId;
  final String productId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final store = accessibleStore(context, storeId);
    void back() => context.go('/products');
    if (store == null) {
      return PageBody(title: tr('product'), onBack: back, child: NotFoundBody(onBack: back));
    }
    return StoreStreamBuilder<List<Product>>(
      stores: [store],
      cacheKey: 'product-detail',
      source: (repo) => repo.products(includeInactive: true),
      builder: (context, data) {
        final match = (data[store.id] ?? const <Product>[]).where((p) => p.id == productId);
        if (match.isEmpty) {
          return PageBody(title: tr('product'), onBack: back, child: NotFoundBody(onBack: back));
        }
        final language = context.select<SessionController, String>((s) => s.language);
        return PageBody(
          title: match.first.displayName(language),
          onBack: back,
          child: _ProductBody(store: store, product: match.first),
        );
      },
    );
  }
}

String _reasonLabel(Tr tr, StockMove move) => switch (move.reason) {
      StockReason.sale => tr('stock_sale'),
      StockReason.purchase => tr('stock_purchase'),
      StockReason.adjustment => move.note == 'opening' ? tr('stock_opening') : tr('stock_adjustment'),
      StockReason.voidSale => tr('stock_void_sale'),
    };

class _ProductBody extends StatelessWidget {
  const _ProductBody({required this.store, required this.product});
  final Store store;
  final Product product;

  Future<void> _edit(BuildContext context, Tr tr, StoreRepository repo) async {
    final values = await showFormDialog(
      context,
      title: tr('edit_product'),
      specs: productSpecs(tr, product: product),
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.saveProduct(productFromForm(values, existing: product)),
      done: tr('saved'),
    );
  }

  Future<void> _adjust(BuildContext context, Tr tr, StoreRepository repo) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('adjust_stock'),
      specs: [
        ChoiceSpec(
          'direction',
          tr('adjustment_direction'),
          {'in': tr('stock_add'), 'out': tr('stock_remove')},
          initial: 'in',
        ),
        TextSpec('qty', tr('quantity'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.quantity),
        TextSpec('note', tr('reason'), validator: v.maxLength(200, isRequired: true)),
      ],
    );
    if (values == null || !context.mounted) return;
    final delta = values.stock('qty') * (values.choice('direction') == 'in' ? 1 : -1);
    runWrite(
      context,
      tr,
      () => repo.adjustStock(productId: product.id, deltaMilli: delta, note: values.text('note')),
      done: tr('saved'),
    );
  }

  Future<void> _toggleActive(BuildContext context, Tr tr, StoreRepository repo) async {
    if (product.active) {
      final confirmed = await confirmDialog(
        context,
        title: tr('deactivate_product'),
        message: tr('deactivate_product_body'),
        confirmLabel: tr('deactivate'),
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    runWrite(context, tr, () => repo.setProductActive(product.id, !product.active), done: tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.read<SessionController>();
    final repo = session.repositoryFor(store.id);
    final columns = <TableCol<StockMove>>[
      TableCol.dateTime(tr('date'), (m) => m.at),
      TableCol.text(tr('reason'), (m) => _reasonLabel(tr, m)),
      TableCol.qty(tr('change'), (m) => m.deltaMilli),
      TableCol.text(tr('note'), (m) => m.note == 'opening' ? '' : m.note, sortable: false),
      TableCol.text(tr('by'), (m) => m.byName),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: TileGrid(
            children: [
              StatTile(
                label: tr('stock'),
                value: '${formatQuantity(product.stockMilli)} ${unitLabel(tr, product.unit)}',
                icon: product.isLowStock ? Icons.warning_amber_rounded : null,
                color: KiranaColors.warning,
              ),
              StatTile(label: tr('low_stock_level'), value: formatQuantity(product.lowStockMilli)),
              StatTile(label: tr('price'), value: formatRupees(product.pricePaise)),
              StatTile(label: tr('cost'), value: formatRupees(product.costPaise)),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Muted('${tr('store')}: ${store.name}'),
            Muted('${tr('product_name')}: ${product.name}'),
            if (product.nameTe.isNotEmpty) Muted('${tr('product_name_te')}: ${product.nameTe}'),
            if (product.barcode.isNotEmpty) Muted('${tr('barcode')}: ${product.barcode}'),
            if (product.category.isNotEmpty) Muted('${tr('category')}: ${product.category}'),
          ],
        ),
        const SizedBox(height: kGap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _adjust(context, tr, repo),
              icon: const Icon(Icons.exposure),
              label: Text(tr('adjust_stock')),
            ),
            OutlinedButton.icon(
              onPressed: () => _edit(context, tr, repo),
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('edit')),
            ),
            OutlinedButton.icon(
              onPressed: () => _toggleActive(context, tr, repo),
              icon: Icon(product.active ? Icons.block : Icons.check_circle_outline),
              label: Text(product.active ? tr('deactivate') : tr('activate')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(tr('movement_history'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StoreStreamBuilder<List<StockMove>>(
          stores: [store],
          cacheKey: 'moves-${product.id}',
          source: (r) => r.stockMoves(product.id, limit: 500),
          builder: (context, data) => AdminTable<StockMove>(
            columns: columns,
            rows: data[store.id] ?? const [],
            sortColumn: 0,
            ascending: false,
            emptyMessage: tr('no_movements'),
          ),
        ),
      ],
    );
  }
}
