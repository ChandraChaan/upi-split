import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    final theme = Theme.of(context);
    return Live<List<Product>>(
      stream: (repo) => repo.products(includeInactive: true),
      loading: const Scaffold(body: LoadingState()),
      builder: (context, products) {
        final matches = products.where((p) => p.id == productId);
        if (matches.isEmpty) {
          return Scaffold(
            appBar: KiranaBar(title: tr('product')),
            body: EmptyState(
              icon: Icons.inventory_2_outlined,
              message: tr('no_data'),
            ),
          );
        }
        final p = matches.first;
        final unit = unitLabel(tr, p.unit);
        return Scaffold(
          appBar: KiranaBar(
            title: p.displayName(language),
            actions: [
              if (manager)
                IconButton(
                  key: const Key('product_edit'),
                  tooltip: tr('edit'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => push(context, ProductFormScreen(product: p)),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('stock_on_hand'),
                        style: theme.textTheme.titleMedium,
                      ),
                      BigNumber(
                        '${formatQuantity(p.stockMilli)} $unit',
                        color: p.stockMilli < 0
                            ? KiranaColors.dues
                            : p.isLowStock
                            ? KiranaColors.warning
                            : null,
                        style: theme.textTheme.displaySmall,
                      ),
                      if (p.stockMilli < 0) Text(tr('negative_stock_hint')),
                      const Divider(height: 24),
                      LabelValue(
                        tr('price'),
                        '${formatRupees(p.pricePaise)} / $unit',
                      ),
                      if (manager)
                        LabelValue(
                          tr('cost'),
                          '${formatRupees(p.costPaise)} / $unit',
                        ),
                      if (p.category.isNotEmpty)
                        LabelValue(tr('category'), p.category),
                      if (p.barcode.isNotEmpty)
                        LabelValue(tr('barcode'), p.barcode),
                      if (p.lowStockMilli > 0)
                        LabelValue(
                          tr('low_stock_level'),
                          formatQuantity(p.lowStockMilli),
                        ),
                      if (!p.active)
                        Flag(tr('inactive'), color: KiranaColors.warning),
                    ],
                  ),
                ),
              ),
              if (manager) ...[
                const SizedBox(height: 10),
                TwoColumn(
                  children: [
                    FilledButton(
                      key: const Key('stock_adjust'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () => showSheet<void>(
                        context,
                        (_) => _AdjustSheet(product: p),
                      ),
                      child: Text(
                        tr('adjust_stock'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    OutlinedButton(
                      key: const Key('product_active_toggle'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () => _toggleActive(context, p),
                      child: Text(
                        p.active ? tr('deactivate') : tr('activate'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
              SectionTitle(tr('stock_history')),
              Live<List<StockMove>>(
                id: p.id,
                stream: (repo) => repo.stockMoves(p.id),
                builder: (context, moves) {
                  if (moves.isEmpty) {
                    return EmptyState(
                      icon: Icons.history,
                      message: tr('no_entries'),
                    );
                  }
                  return Column(
                    children: [
                      for (final m in moves)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(stockReasonLabel(tr, m.reason)),
                          subtitle: Text(
                            [
                              if (m.note == 'opening')
                                tr('opening_stock')
                              else if (m.note.isNotEmpty)
                                m.note,
                              '${formatDateTime(m.at, language)} · ${m.byName}',
                            ].join('\n'),
                          ),
                          trailing: Text(
                            '${m.deltaMilli > 0 ? '+' : ''}${formatQuantity(m.deltaMilli)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: m.deltaMilli < 0
                                  ? KiranaColors.dues
                                  : KiranaColors.received,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleActive(BuildContext context, Product p) async {
    final tr = context.trNow;
    final repo = context.session.repository;
    if (p.active) {
      final ok = await confirm(
        context,
        title: tr('deactivate'),
        body: tr('deactivate_body'),
        action: tr('deactivate'),
        destructive: true,
      );
      if (!ok || !context.mounted) return;
    }
    repo.setProductActive(p.id, !p.active);
    showMessage(context, tr('saved'));
  }
}

class _AdjustSheet extends StatefulWidget {
  const _AdjustSheet({required this.product});

  final Product product;

  @override
  State<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends State<_AdjustSheet> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _adding = true;
  String? _reason;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final delta = parseQuantity(_qty.text)!;
    final note = [
      ?_reason,
      if (_note.text.trim().isNotEmpty) _note.text.trim(),
    ].join(' - ');
    context.session.repository.adjustStock(
      productId: widget.product.id,
      deltaMilli: _adding ? delta : -delta,
      note: note,
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final reasons = [
      tr('adjust_count'),
      tr('adjust_damaged'),
      tr('adjust_expired'),
      tr('adjust_own_use'),
    ];
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('adjust_stock'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(tr('add_stock'))),
              ButtonSegment(value: false, label: Text(tr('remove_stock'))),
            ],
            selected: {_adding},
            onSelectionChanged: (s) => setState(() => _adding = s.first),
          ),
          const SizedBox(height: 12),
          QuantityField(
            key: const Key('adjust_qty'),
            controller: _qty,
            autofocus: true,
            label: tr('quantity'),
            validator: V.quantity(tr),
          ),
          const SizedBox(height: 12),
          Text(tr('reason')),
          Wrap(
            spacing: 8,
            children: [
              for (final r in reasons)
                ChoiceChip(
                  label: Text(r),
                  selected: _reason == r,
                  onSelected: (on) => setState(() => _reason = on ? r : null),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('adjust_note'),
            controller: _note,
            decoration: InputDecoration(labelText: tr('note')),
            // Either a chip or typed words: an adjustment needs a reason.
            validator: (v) => _reason == null && (v == null || v.trim().isEmpty)
                ? tr('reason_required')
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('adjust_save'),
            onPressed: _save,
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}

class ProductFormScreen extends StatelessWidget {
  const ProductFormScreen({super.key, this.product});

  final Product? product;

  @override
  Widget build(BuildContext context) {
    return Live<List<Product>>(
      stream: (repo) => repo.products(includeInactive: true),
      loading: const Scaffold(body: LoadingState()),
      builder: (context, all) => _ProductForm(product: product, all: all),
    );
  }
}

class _ProductForm extends StatefulWidget {
  const _ProductForm({required this.product, required this.all});

  final Product? product;
  final List<Product> all;

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final Product? _p = widget.product;
  late final _name = TextEditingController(text: _p?.name ?? '');
  late final _nameTe = TextEditingController(text: _p?.nameTe ?? '');
  late final _barcode = TextEditingController(text: _p?.barcode ?? '');
  late final _category = TextEditingController(text: _p?.category ?? '');
  late final _price = TextEditingController(
    text: _p == null ? '' : formatRupees(_p.pricePaise, symbol: false),
  );
  late final _cost = TextEditingController(
    text: _p == null || _p.costPaise == 0
        ? ''
        : formatRupees(_p.costPaise, symbol: false),
  );
  late final _low = TextEditingController(
    text: _p == null || _p.lowStockMilli == 0
        ? ''
        : formatQuantity(_p.lowStockMilli),
  );
  final _opening = TextEditingController();
  late Unit _unit = _p?.unit ?? Unit.piece;

  @override
  void dispose() {
    _name.dispose();
    _nameTe.dispose();
    _barcode.dispose();
    _category.dispose();
    _price.dispose();
    _cost.dispose();
    _low.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final product = Product(
      id: _p?.id ?? '',
      name: _name.text.trim(),
      nameTe: _nameTe.text.trim(),
      barcode: _barcode.text.trim(),
      category: _category.text.trim(),
      unit: _unit,
      pricePaise: parseRupeesOrZero(_price.text),
      costPaise: parseRupeesOrZero(_cost.text),
      lowStockMilli: parseQuantityOrZero(_low.text) ?? 0,
      active: _p?.active ?? true,
    );
    final opening = _p == null ? parseQuantityOrZero(_opening.text) : null;
    try {
      context.session.repository.saveProduct(
        product,
        openingStockMilli: opening,
      );
    } on InvalidOperation {
      showMessage(context, tr('error_generic'));
      return;
    }
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final categories =
        widget.all
            .map((p) => p.category.trim())
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: KiranaBar(
        title: _p == null ? tr('add_product') : tr('edit_product'),
      ),
      body: Form(
        key: _form,
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('product_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('name_english')),
              validator: V.required(tr),
            ),
            gap,
            TextFormField(
              key: const Key('product_name_te'),
              controller: _nameTe,
              decoration: InputDecoration(labelText: tr('name_telugu')),
            ),
            gap,
            TextFormField(
              key: const Key('product_barcode'),
              controller: _barcode,
              decoration: InputDecoration(labelText: tr('barcode')),
              validator: (v) {
                final code = v?.trim() ?? '';
                if (code.isEmpty) return null;
                final clash = widget.all.any(
                  (p) => p.id != _p?.id && p.barcode == code,
                );
                return clash ? tr('barcode_in_use') : null;
              },
            ),
            gap,
            TextFormField(
              controller: _category,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('category')),
            ),
            if (categories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final c in categories)
                      ActionChip(
                        label: Text(c),
                        onPressed: () => setState(() => _category.text = c),
                      ),
                  ],
                ),
              ),
            gap,
            Text(tr('unit'), style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8,
              children: [
                for (final u in Unit.values)
                  ChoiceChip(
                    label: Text(unitLabel(tr, u)),
                    selected: _unit == u,
                    onSelected: (_) => setState(() => _unit = u),
                  ),
              ],
            ),
            gap,
            AmountField(
              key: const Key('product_price'),
              controller: _price,
              label: tr('price'),
              validator: V.amount(tr),
            ),
            gap,
            AmountField(
              key: const Key('product_cost'),
              controller: _cost,
              label: tr('cost'),
              validator: V.amount(tr, optional: true),
            ),
            gap,
            QuantityField(
              key: const Key('product_low'),
              controller: _low,
              label: tr('low_stock_level'),
              validator: V.quantity(tr, optional: true),
            ),
            if (_p == null) ...[
              gap,
              QuantityField(
                key: const Key('product_opening'),
                controller: _opening,
                label: tr('opening_stock'),
                validator: V.quantity(tr, optional: true),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('product_save'),
          onPressed: _save,
          child: Text(tr('save')),
        ),
      ),
    );
  }
}
