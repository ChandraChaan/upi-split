import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ManagerOnly(child: _SupplierList());
  }
}

class _SupplierList extends StatelessWidget {
  const _SupplierList();

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: KiranaBar(title: tr('suppliers')),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          key: const Key('supplier_add'),
          icon: const Icon(Icons.add),
          label: Text(tr('add_supplier')),
          onPressed: () => push(context, const SupplierFormScreen()),
        ),
      ),
      body: Live<List<Supplier>>(
        stream: (repo) => repo.suppliers(),
        builder: (context, suppliers) {
          if (suppliers.isEmpty) {
            return EmptyState(
              icon: Icons.local_shipping_outlined,
              message: tr('no_suppliers'),
            );
          }
          final owed = suppliers.fold<int>(
            0,
            (sum, s) => sum + (s.balancePaise > 0 ? s.balancePaise : 0),
          );
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: suppliers.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: LabelValue(
                    tr('total_payable'),
                    formatRupees(owed),
                    color: KiranaColors.dues,
                    strong: true,
                  ),
                );
              }
              final s = suppliers[i - 1];
              return ListTile(
                key: ValueKey('supplier_${s.id}'),
                minTileHeight: 64,
                title: Text(s.name, style: theme.textTheme.titleMedium),
                subtitle: s.phone.isEmpty ? null : Text(s.phone),
                trailing: Text(
                  formatRupees(s.balancePaise),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: s.balancePaise > 0
                        ? KiranaColors.dues
                        : KiranaColors.received,
                  ),
                ),
                onTap: () =>
                    push(context, SupplierDetailScreen(supplierId: s.id)),
              );
            },
          );
        },
      ),
    );
  }
}

class SupplierDetailScreen extends StatelessWidget {
  const SupplierDetailScreen({super.key, required this.supplierId});

  final String supplierId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final theme = Theme.of(context);
    return ManagerOnly(
      child: Live<List<Supplier>>(
        stream: (repo) => repo.suppliers(),
        loading: const Scaffold(body: LoadingState()),
        builder: (context, suppliers) {
          final matches = suppliers.where((s) => s.id == supplierId);
          if (matches.isEmpty) {
            return Scaffold(
              appBar: KiranaBar(title: tr('supplier')),
              body: EmptyState(
                icon: Icons.local_shipping_outlined,
                message: tr('no_data'),
              ),
            );
          }
          final s = matches.first;
          return Scaffold(
            appBar: KiranaBar(
              title: s.name,
              actions: [
                IconButton(
                  tooltip: tr('edit'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      push(context, SupplierFormScreen(supplier: s)),
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
                          tr('amount_payable'),
                          style: theme.textTheme.titleMedium,
                        ),
                        BigNumber(
                          formatRupees(s.balancePaise),
                          color: s.balancePaise > 0
                              ? KiranaColors.dues
                              : KiranaColors.received,
                          style: theme.textTheme.displaySmall,
                        ),
                        if (s.phone.isNotEmpty) Text(s.phone),
                        if (s.address.isNotEmpty) Text(s.address),
                        if (s.gstin.isNotEmpty)
                          Text('${tr('gstin')}: ${s.gstin}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TwoColumn(
                  children: [
                    FilledButton(
                      key: const Key('supplier_purchase'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () =>
                          push(context, PurchaseScreen(supplier: s)),
                      child: Text(
                        tr('record_purchase'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    OutlinedButton(
                      key: const Key('supplier_payment'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      onPressed: () => showSheet<void>(
                        context,
                        (_) => _SupplierPaymentSheet(supplier: s),
                      ),
                      child: Text(
                        tr('pay_supplier'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                SectionTitle(tr('transactions')),
                Live<List<SupplierTxn>>(
                  id: s.id,
                  stream: (repo) => repo.supplierTxns(s.id),
                  builder: (context, txns) {
                    if (txns.isEmpty) {
                      return EmptyState(
                        icon: Icons.history,
                        message: tr('no_entries'),
                      );
                    }
                    return Column(
                      children: [
                        for (final t in txns)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              t.kind == SupplierTxnKind.purchase
                                  ? tr('supplier_txn_purchase')
                                  : tr('supplier_txn_payment'),
                            ),
                            subtitle: Text(
                              [
                                if (t.method != null)
                                  methodLabel(tr, t.method!),
                                if (t.items.isNotEmpty)
                                  t.items
                                      .map(
                                        (i) => i.amountPaise > 0
                                            ? '${i.name} ${formatRupees(i.amountPaise)}'
                                            : i.name,
                                      )
                                      .join(', '),
                                if (t.note.isNotEmpty) t.note,
                                '${formatDateTime(t.at, language)} · ${t.byName}',
                              ].join('\n'),
                            ),
                            trailing: Text(
                              '${t.kind == SupplierTxnKind.purchase ? '+' : '-'}${formatRupees(t.amountPaise)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: t.kind == SupplierTxnKind.purchase
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
      ),
    );
  }
}

class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({super.key, this.supplier});

  final Supplier? supplier;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );
  late final _gstin = TextEditingController(text: widget.supplier?.gstin ?? '');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _gstin.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    context.session.repository.saveSupplier(
      id: widget.supplier?.id,
      name: _name.text,
      phone: _phone.text,
      address: _address.text,
      gstin: _gstin.text,
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: KiranaBar(
        title: widget.supplier == null
            ? tr('add_supplier')
            : tr('edit_supplier'),
      ),
      body: Form(
        key: _form,
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('supplier_name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('name')),
              validator: V.required(tr),
            ),
            gap,
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('phone')),
              validator: V.phone(tr),
            ),
            gap,
            TextFormField(
              controller: _address,
              decoration: InputDecoration(labelText: tr('address')),
            ),
            gap,
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('gstin')),
              validator: V.gstin(tr),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('supplier_save'),
          onPressed: _save,
          child: Text(tr('save')),
        ),
      ),
    );
  }
}

class _SupplierPaymentSheet extends StatefulWidget {
  const _SupplierPaymentSheet({required this.supplier});

  final Supplier supplier;

  @override
  State<_SupplierPaymentSheet> createState() => _SupplierPaymentSheetState();
}

class _SupplierPaymentSheetState extends State<_SupplierPaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    context.session.repository.recordSupplierPayment(
      supplierId: widget.supplier.id,
      amountPaise: parseRupees(_amount.text)!,
      method: _method,
      note: _note.text,
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final balance = widget.supplier.balancePaise;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('pay_supplier'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AmountField(
            key: const Key('supplier_pay_amount'),
            controller: _amount,
            autofocus: true,
            big: true,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          if (balance > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                label: Text(
                  tr('full_amount', {'amount': formatRupees(balance)}),
                ),
                onPressed: () => setState(
                  () => _amount.text = formatRupees(balance, symbol: false),
                ),
              ),
            ),
          const SizedBox(height: 8),
          MethodPicker(
            value: _method,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('note')),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(tr('save'))),
        ],
      ),
    );
  }
}

class _DraftLine {
  _DraftLine(this.product, this.qtyMilli, this.costPaise);
  final Product product;
  final int qtyMilli;
  final int costPaise;
  int get valuePaise => lineValue(costPaise, qtyMilli);
}

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  final List<_DraftLine> _lines = [];
  PaymentMethod _method = PaymentMethod.cash;

  /// The bill amount follows the lines until the user types their own.
  bool _amountTouched = false;

  @override
  void dispose() {
    _amount.dispose();
    _paid.dispose();
    _note.dispose();
    super.dispose();
  }

  void _syncAmount() {
    if (_amountTouched) return;
    final sum = _lines.fold<int>(0, (total, l) => total + l.valuePaise);
    _amount.text = sum > 0 ? formatRupees(sum, symbol: false) : '';
  }

  Future<void> _addLine() async {
    final line = await showSheet<_DraftLine>(
      context,
      (_) => const _StockInSheet(),
    );
    if (line == null || !mounted) return;
    setState(() {
      _lines.add(line);
      _syncAmount();
    });
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    try {
      context.session.repository.recordSupplierPurchase(
        supplierId: widget.supplier.id,
        amountPaise: parseRupees(_amount.text)!,
        paidPaise: parseRupeesOrZero(_paid.text),
        method: _method,
        note: _note.text,
        lines: [
          for (final l in _lines)
            StockInLine(
              product: l.product,
              qtyMilli: l.qtyMilli,
              costPaise: l.costPaise,
            ),
        ],
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
    final language = context.lang;
    final paid = parseRupeesOrZero(_paid.text);
    return Scaffold(
      appBar: KiranaBar(title: tr('record_purchase')),
      body: Form(
        key: _form,
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.supplier.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SectionTitle(tr('stock_in_optional')),
            for (var i = 0; i < _lines.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_lines[i].product.displayName(language)),
                subtitle: Text(
                  '${formatQuantity(_lines[i].qtyMilli)} × ${formatRupees(_lines[i].costPaise)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatRupees(_lines[i].valuePaise)),
                    IconButton(
                      tooltip: tr('remove_item'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _lines.removeAt(i);
                        _syncAmount();
                      }),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              key: const Key('purchase_add_line'),
              icon: const Icon(Icons.add),
              label: Text(tr('add_stock_line')),
              onPressed: _addLine,
            ),
            const SizedBox(height: 16),
            AmountField(
              key: const Key('purchase_amount'),
              controller: _amount,
              big: true,
              label: tr('bill_amount'),
              validator: V.amount(tr),
              onChanged: (_) => setState(() => _amountTouched = true),
            ),
            const SizedBox(height: 12),
            AmountField(
              key: const Key('purchase_paid'),
              controller: _paid,
              label: tr('paid_now'),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                final error = V.amount(tr, optional: true)(v);
                if (error != null) return error;
                final total = parseRupees(_amount.text);
                return total != null && parseRupeesOrZero(v ?? '') > total
                    ? tr('paid_exceeds_amount')
                    : null;
              },
            ),
            if (paid > 0) ...[
              const SizedBox(height: 12),
              MethodPicker(
                value: _method,
                onChanged: (m) => setState(() => _method = m),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(labelText: tr('note')),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('purchase_save'),
          onPressed: _save,
          child: Text(tr('save')),
        ),
      ),
    );
  }
}

/// Choose a product from the catalogue, then its quantity and purchase cost.
class _StockInSheet extends StatefulWidget {
  const _StockInSheet();

  @override
  State<_StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<_StockInSheet> {
  final _form = GlobalKey<FormState>();
  final _query = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  Product? _product;

  @override
  void dispose() {
    _query.dispose();
    _qty.dispose();
    _cost.dispose();
    super.dispose();
  }

  void _choose(Product p) {
    setState(() {
      _product = p;
      _cost.text = p.costPaise > 0
          ? formatRupees(p.costPaise, symbol: false)
          : '';
    });
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      _DraftLine(
        _product!,
        parseQuantity(_qty.text)!,
        parseRupees(_cost.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final product = _product;
    if (product != null) {
      final unit = unitLabel(tr, product.unit);
      return Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              product.displayName(language),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            QuantityField(
              key: const Key('stockin_qty'),
              controller: _qty,
              autofocus: true,
              label: tr('quantity_in', {'unit': unit}),
              validator: V.quantity(tr),
            ),
            const SizedBox(height: 12),
            AmountField(
              key: const Key('stockin_cost'),
              controller: _cost,
              label: tr('cost_per', {'unit': unit}),
              validator: V.amount(tr),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('stockin_done'),
              onPressed: _done,
              child: Text(tr('add')),
            ),
            TextButton(
              onPressed: () => setState(() => _product = null),
              child: Text(tr('back_to_list')),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('stockin_search'),
          controller: _query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: tr('billing_search_hint'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 360,
          child: Live<List<Product>>(
            stream: (repo) => repo.products(),
            builder: (context, products) {
              final q = _query.text.trim().toLowerCase();
              final list = products
                  .where(
                    (p) =>
                        p.name.toLowerCase().contains(q) ||
                        p.nameTe.toLowerCase().contains(q) ||
                        p.barcode.contains(q),
                  )
                  .toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.search_off,
                  message: tr('no_matches'),
                );
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ListTile(
                  key: ValueKey('stockin_product_${list[i].id}'),
                  title: Text(list[i].displayName(language)),
                  subtitle: Text(
                    tr('stock_short', {
                      'qty': formatQuantity(list[i].stockMilli),
                    }),
                  ),
                  onTap: () => _choose(list[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
