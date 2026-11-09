import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import '../widgets/line_sheet.dart';
import 'checkout_screen.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final Cart _cart = Cart();
  final _query = TextEditingController();
  final _focus = FocusNode();
  String? _category;
  List<Product> _products = const [];

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Product> _matches() {
    final q = _query.text.trim().toLowerCase();
    return _products.where((p) {
      if (_category != null && p.category != _category) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.nameTe.toLowerCase().contains(q) ||
          p.barcode.contains(q);
    }).toList();
  }

  CartLine? _lineFor(Product p) {
    for (final line in _cart.lines) {
      if (line.productId == p.id) return line;
    }
    return null;
  }

  void _clearSearch() {
    _query.clear();
    _focus.requestFocus();
    setState(() {});
  }

  /// Hardware scanners type the code and press Enter. So does a person who
  /// has narrowed the list to one item.
  void _onSubmitted(String value) {
    final tr = context.trNow;
    final code = value.trim();
    if (code.isEmpty) {
      _focus.requestFocus();
      return;
    }
    final exact = _products.where(
      (p) => p.barcode.isNotEmpty && p.barcode == code,
    );
    final matches = _matches();
    if (exact.isNotEmpty) {
      _tapProduct(exact.first);
      _clearSearch();
    } else if (matches.length == 1) {
      _tapProduct(matches.single);
      _clearSearch();
    } else {
      if (matches.isEmpty) showMessage(context, tr('barcode_not_found'));
      _focus.requestFocus();
    }
  }

  Future<void> _tapProduct(Product p) async {
    final line = _lineFor(p);
    if (isLooseUnit(p.unit)) {
      if (line != null) {
        await _editLine(line, p.displayName(context.session.language));
      } else {
        await _addLoose(p);
      }
      return;
    }
    setState(() => _cart.addProduct(p, 1000));
  }

  Future<void> _addLoose(Product p) async {
    final edit = await showSheet<LineEdit>(
      context,
      (_) => LineSheet(
        title: p.displayName(context.session.language),
        unit: p.unit,
        pricePaise: p.pricePaise,
      ),
    );
    if (edit == null || !mounted) return;
    setState(() {
      _cart.addProduct(p, edit.qtyMilli);
      _lineFor(p)?.pricePaise = edit.pricePaise;
    });
  }

  Future<void> _editLine(CartLine line, String title) async {
    final edit = await showSheet<LineEdit>(
      context,
      (_) => LineSheet(
        title: title,
        unit: line.unit,
        qtyMilli: line.qtyMilli,
        pricePaise: line.pricePaise,
        canRemove: true,
      ),
    );
    if (edit == null || !mounted) return;
    setState(() => applyLineEdit(_cart, line, edit));
  }

  void _step(CartLine line, int direction) {
    setState(() {
      final next = line.qtyMilli + direction * 1000;
      if (next <= 0) {
        _cart.lines.remove(line);
      } else {
        line.qtyMilli = next;
      }
    });
  }

  Future<void> _addCustom() async {
    final added = await showSheet<CustomLine>(
      context,
      (_) => const CustomLineSheet(),
    );
    if (added == null || !mounted) return;
    setState(
      () => _cart.addCustom(
        added.name,
        added.pricePaise,
        qtyMilli: added.qtyMilli,
      ),
    );
  }

  Future<void> _checkout() async {
    await push(context, CheckoutScreen(cart: _cart));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    return Scaffold(
      appBar: KiranaBar(title: tr('billing')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('billing_search'),
                    controller: _query,
                    focusNode: _focus,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _onSubmitted,
                    // Keeps focus in the field so the next scan lands here.
                    onEditingComplete: () {},
                    decoration: InputDecoration(
                      hintText: tr('billing_search_hint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('add_custom_line'),
                  iconSize: 28,
                  constraints: const BoxConstraints.tightFor(
                    width: 56,
                    height: 56,
                  ),
                  tooltip: tr('custom_item'),
                  icon: const Icon(Icons.post_add),
                  onPressed: _addCustom,
                ),
              ],
            ),
          ),
          Expanded(
            child: Live<List<Product>>(
              stream: (repo) => repo.products(),
              builder: (context, products) {
                _products = products;
                if (products.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: tr('billing_no_products'),
                    actionLabel: tr('custom_item'),
                    onAction: _addCustom,
                  );
                }
                final categories =
                    products
                        .map((p) => p.category.trim())
                        .where((c) => c.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                final matches = _matches();
                return Column(
                  children: [
                    if (categories.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            _chip(tr('all'), null),
                            for (final c in categories) _chip(c, c),
                          ],
                        ),
                      ),
                    Expanded(
                      child: matches.isEmpty
                          ? EmptyState(
                              icon: Icons.search_off,
                              message: tr('no_matches'),
                              actionLabel: tr('custom_item'),
                              onAction: _addCustom,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: matches.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) => _ProductRow(
                                product: matches[i],
                                line: _lineFor(matches[i]),
                                language: language,
                                tr: tr,
                                onTap: () => _tapProduct(matches[i]),
                                onStep: _step,
                                onEditQty: _editLine,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (!_cart.isEmpty)
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr('items_count', {
                              'count': '${_cart.lines.length}',
                            }),
                          ),
                          BigNumber(
                            formatRupees(_cart.totalPaise),
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FilledButton(
                        key: const Key('billing_checkout'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(120, 56),
                        ),
                        onPressed: _checkout,
                        child: Text(
                          tr('checkout'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, String? value) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: _category == value,
      onSelected: (_) => setState(() => _category = value),
    ),
  );
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.line,
    required this.language,
    required this.tr,
    required this.onTap,
    required this.onStep,
    required this.onEditQty,
  });

  final Product product;
  final CartLine? line;
  final String language;
  final Tr tr;
  final VoidCallback onTap;
  final void Function(CartLine line, int direction) onStep;
  final void Function(CartLine line, String title) onEditQty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product.displayName(language);
    final current = line;
    final stockColor = product.stockMilli <= 0
        ? KiranaColors.dues
        : product.isLowStock
        ? KiranaColors.warning
        : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      key: ValueKey('product_${product.id}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text:
                                '${formatRupees(product.pricePaise)} / ${unitLabel(tr, product.unit)}   ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: tr('stock_short', {
                              'qty': formatQuantity(product.stockMilli),
                            }),
                            style: TextStyle(color: stockColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (current == null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    Icons.add_circle,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('minus_${product.id}'),
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => onStep(current, -1),
                    ),
                    InkWell(
                      key: ValueKey('qty_${product.id}'),
                      onTap: () => onEditQty(current, name),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 48,
                        ),
                        child: Center(
                          child: Text(
                            formatQuantity(current.qtyMilli),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('plus_${product.id}'),
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => onStep(current, 1),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
