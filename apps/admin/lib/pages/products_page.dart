import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../data/catalogue_writer.dart';
import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/platform.dart';
import '../utils/product_import.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

/// Fields shared by adding and editing a product.
List<FormSpec> productSpecs(
  Tr tr, {
  Product? product,
  List<Store> pickFrom = const [],
  List<String> categories = const [],
}) {
  final v = Validators(tr);
  String money(int paise) => formatRupees(paise, symbol: false).replaceAll(',', '');
  const decimal = TextInputType.numberWithOptions(decimal: true);
  return [
    if (pickFrom.isNotEmpty)
      ChoiceSpec('store', tr('store'), storeOptions(pickFrom),
          initial: pickFrom.length == 1 ? pickFrom.first.id : null),
    TextSpec('name', tr('product_name'),
        initial: product?.name ?? '', validator: v.maxLength(120, isRequired: true)),
    TextSpec('nameTe', tr('product_name_te'),
        initial: product?.nameTe ?? '', validator: v.maxLength(120)),
    TextSpec('barcode', tr('barcode'),
        initial: product?.barcode ?? '', validator: v.maxLength(40)),
    TextSpec('category', tr('category'),
        initial: product?.category ?? '',
        suggestions: categories,
        validator: v.maxLength(60)),
    ChoiceSpec(
      'unit',
      tr('unit'),
      {for (final u in Unit.values) u.name: unitLabel(tr, u)},
      initial: product?.unit.name ?? Unit.piece.name,
    ),
    TextSpec('price', tr('price'),
        initial: product == null ? '' : money(product.pricePaise),
        keyboard: decimal,
        validator: v.money,
        formatters: [moneyInputFormatter]),
    TextSpec('cost', tr('cost'),
        initial: product == null ? '' : money(product.costPaise),
        keyboard: decimal,
        validator: v.money,
        formatters: [moneyInputFormatter]),
    if (product == null)
      TextSpec('stock', tr('opening_stock'), keyboard: decimal, validator: v.stock),
    TextSpec('low', tr('low_stock_level'),
        initial: product == null || product.lowStockMilli == 0
            ? ''
            : formatQuantity(product.lowStockMilli),
        helper: tr('low_stock_level_hint'),
        keyboard: decimal,
        validator: v.stock),
  ];
}

Product productFromForm(FormValues v, {Product? existing}) => Product(
      id: existing?.id ?? '',
      name: v.text('name'),
      nameTe: v.text('nameTe'),
      barcode: v.text('barcode'),
      category: v.text('category'),
      unit: Unit.values.byName(v.choice('unit') ?? Unit.piece.name),
      pricePaise: v.money('price'),
      costPaise: v.money('cost'),
      lowStockMilli: v.stock('low'),
      active: existing?.active ?? true,
    );

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String _query = '';
  String? _category;
  bool _lowOnly = false;
  bool _showInactive = false;

  Future<void> _add(Tr tr, List<Store> stores, List<String> categories) async {
    final values = await showFormDialog(
      context,
      title: tr('add_product'),
      specs: productSpecs(tr, pickFrom: stores, categories: categories),
    );
    if (values == null || !mounted) return;
    final repo = context.read<SessionController>().repositoryFor(values.choice('store')!);
    runWrite(
      context,
      tr,
      () => repo.saveProduct(productFromForm(values), openingStockMilli: values.stock('stock')),
      done: tr('saved'),
    );
  }

  Future<void> _copy(Tr tr, List<Store> allStores) async {
    final values = await showFormDialog(
      context,
      title: tr('copy_catalogue'),
      description: tr('copy_catalogue_hint'),
      submitLabel: tr('next'),
      specs: [
        ChoiceSpec('source', tr('copy_from'), storeOptions(allStores)),
        ChoiceSpec('target', tr('copy_to'), storeOptions(allStores)),
      ],
    );
    if (values == null || !mounted) return;
    final source = values.choice('source')!;
    final target = values.choice('target')!;
    if (source == target) {
      showMessage(context, tr('copy_same_store'));
      return;
    }
    final session = context.read<SessionController>();
    final targetRepo = session.repositoryFor(target);
    try {
      final sourceProducts = await fetchAllProducts(session.repositoryFor(source));
      final targetProducts = await fetchAllProducts(targetRepo);
      if (!mounted) return;
      final toCopy = productsToCopy(sourceProducts, targetProducts);
      if (toCopy.isEmpty) {
        showMessage(context, tr('copy_nothing'));
        return;
      }
      final confirmed = await confirmDialog(
        context,
        title: tr('copy_catalogue'),
        message: tr('copy_confirm', {
          'count': '${toCopy.length}',
          'skipped': '${sourceProducts.where((p) => p.active).length - toCopy.length}',
        }),
        confirmLabel: tr('copy'),
      );
      if (!confirmed || !mounted) return;
      CatalogueWriter(targetRepo).write(
        [for (final p in toCopy) CatalogueLine(p)],
        label: 'copyCatalogue',
      );
      showMessage(context, tr('copy_done', {'count': '${toCopy.length}'}));
    } catch (e) {
      debugPrint('Copy failed: $e');
      if (mounted) showMessage(context, tr('error_generic'));
    }
  }

  void _template(Tr tr) {
    downloadTextFile(
      'products_template.csv',
      buildCsv([
        [for (final c in ProductCsvColumn.values) tr(productCsvHeaderKeys[c]!)],
        const ['Toor Dal 1kg', 'కందిపప్పు 1 కిలో', '8901234567890', 'Pulses', 'packet', '165', '148', '20', '5'],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.select<SessionController, String>((s) => s.language);
    final session = context.watch<SessionController>();
    final stores = scopedStores(context);
    return StoreStreamBuilder<List<Product>>(
      stores: stores,
      cacheKey: 'products',
      source: (repo) => repo.products(includeInactive: true),
      builder: (context, byStore) {
        final all = flatten(stores, byStore);
        final categories = ({
          for (final r in all)
            if (r.item.category.isNotEmpty) r.item.category,
        }).toList()
          ..sort();
        final selectedCategory = categories.contains(_category) ? _category : null;
        final rows = all.where((row) {
          final p = row.item;
          if (!_showInactive && !p.active) return false;
          if (_lowOnly && !(p.active && p.isLowStock)) return false;
          if (selectedCategory != null && p.category != selectedCategory) return false;
          if (_query.isEmpty) return true;
          return p.name.toLowerCase().contains(_query) ||
              p.nameTe.contains(_query) ||
              p.barcode.contains(_query);
        }).toList();

        final columns = <TableCol<StoreItem<Product>>>[
          TableCol.text(tr('product'), (r) => r.item.displayName(language)),
          TableCol.text(tr('barcode'), (r) => r.item.barcode),
          if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
          TableCol.text(tr('category'), (r) => r.item.category),
          TableCol.qty(tr('stock'), (r) => r.item.stockMilli),
          TableCol.text(tr('unit'), (r) => unitLabel(tr, r.item.unit)),
          TableCol.money(tr('price'), (r) => r.item.pricePaise),
          TableCol.money(tr('cost'), (r) => r.item.costPaise),
          TableCol(
            tr('status'),
            (r) => !r.item.active
                ? StatusChip(label: tr('inactive'), color: Theme.of(context).colorScheme.outline)
                : r.item.isLowStock
                    ? StatusChip(
                        label: tr('low_stock'),
                        color: KiranaColors.warning,
                        icon: Icons.warning_amber_rounded,
                      )
                    : const Text('-'),
          ),
        ];

        return PageBody(
          title: tr('products'),
          actions: [
            FilledButton.icon(
              onPressed: () => _add(tr, stores, categories),
              icon: const Icon(Icons.add),
              label: Text(tr('add_product')),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go('/products/import'),
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(tr('import_csv')),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => downloadTextFile(
                        'products.csv',
                        buildCsv(productCsvRows(rows.map((r) => r.item).toList(), tr.call)),
                      ),
              icon: const Icon(Icons.download_outlined),
              label: Text(tr('export_csv')),
            ),
            OutlinedButton.icon(
              onPressed: () => _template(tr),
              icon: const Icon(Icons.description_outlined),
              label: Text(tr('download_template')),
            ),
            if (session.stores.length > 1)
              OutlinedButton.icon(
                onPressed: () => _copy(tr, session.stores),
                icon: const Icon(Icons.copy_all_outlined),
                label: Text(tr('copy_catalogue')),
              ),
          ],
          filters: [
            SearchField(
              hint: tr('search_products'),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: DropdownButtonFormField<String>(
                key: ValueKey('category-$selectedCategory-${categories.length}'),
                initialValue: selectedCategory,
                isExpanded: true,
                decoration: InputDecoration(isDense: true, labelText: tr('category')),
                items: [
                  DropdownMenuItem(child: Text(tr('all_categories'))),
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
            ),
            FilterChip(
              label: Text(tr('low_stock')),
              selected: _lowOnly,
              onSelected: (v) => setState(() => _lowOnly = v),
            ),
            FilterChip(
              label: Text(tr('show_inactive')),
              selected: _showInactive,
              onSelected: (v) => setState(() => _showInactive = v),
            ),
          ],
          child: AdminTable<StoreItem<Product>>(
            columns: columns,
            rows: rows,
            sortColumn: 0,
            emptyMessage: all.isEmpty ? tr('no_products') : tr('no_matches'),
            onTap: (r) => context.go('/products/${r.store.id}/${r.item.id}'),
          ),
        );
      },
    );
  }
}
