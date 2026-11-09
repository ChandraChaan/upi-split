import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/platform.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';
import 'suppliers_page.dart';

class SupplierDetailPage extends StatelessWidget {
  const SupplierDetailPage({super.key, required this.storeId, required this.supplierId});
  final String storeId;
  final String supplierId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final store = accessibleStore(context, storeId);
    void back() => context.go('/suppliers');
    if (store == null) {
      return PageBody(title: tr('supplier'), onBack: back, child: NotFoundBody(onBack: back));
    }
    return StoreStreamBuilder<List<Supplier>>(
      stores: [store],
      cacheKey: 'supplier-detail',
      source: (repo) => repo.suppliers(),
      builder: (context, data) {
        final match = (data[store.id] ?? const <Supplier>[]).where((s) => s.id == supplierId);
        if (match.isEmpty) {
          return PageBody(title: tr('supplier'), onBack: back, child: NotFoundBody(onBack: back));
        }
        return PageBody(
          title: match.first.name,
          onBack: back,
          child: _SupplierBody(store: store, supplier: match.first),
        );
      },
    );
  }
}

class _Row {
  const _Row(this.txn, this.balanceAfter);
  final SupplierTxn txn;
  final int balanceAfter;
}

/// Transactions come newest first; balances are worked back from the current one.
List<_Row> _rows(List<SupplierTxn> txns, int current) {
  var balance = current;
  final rows = <_Row>[];
  for (final t in txns) {
    rows.add(_Row(t, balance));
    balance -= t.kind == SupplierTxnKind.purchase ? t.amountPaise : -t.amountPaise;
  }
  return rows;
}

class _SupplierBody extends StatelessWidget {
  const _SupplierBody({required this.store, required this.supplier});
  final Store store;
  final Supplier supplier;

  Future<void> _edit(BuildContext context, Tr tr, StoreRepository repo) async {
    final values = await showFormDialog(
      context,
      title: tr('edit_supplier'),
      specs: supplierSpecs(tr, supplier: supplier),
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.saveSupplier(
        id: supplier.id,
        name: values.text('name'),
        phone: values.text('phone'),
        address: values.text('address'),
        gstin: values.text('gstin').toUpperCase(),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _payment(BuildContext context, Tr tr, StoreRepository repo) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('pay_supplier'),
      specs: [
        TextSpec('amount', tr('amount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.positiveMoney,
            formatters: [moneyInputFormatter]),
        ChoiceSpec('method', tr('payment_method'), {'cash': tr('cash'), 'upi': tr('upi')},
            initial: 'cash'),
        TextSpec('note', tr('note'), validator: v.maxLength(200)),
      ],
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.recordSupplierPayment(
        supplierId: supplier.id,
        amountPaise: values.money('amount'),
        method: values.choice('method') == 'upi' ? PaymentMethod.upi : PaymentMethod.cash,
        note: values.text('note'),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _archive(BuildContext context, Tr tr, StoreRepository repo) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('archive_supplier'),
      message: tr('archive_supplier_body'),
      confirmLabel: tr('archive'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    runWrite(context, tr, () => repo.archiveSupplier(supplier.id));
    context.go('/suppliers');
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.read<SessionController>();
    final repo = session.repositoryFor(store.id);
    final columns = <TableCol<_Row>>[
      TableCol.dateTime(tr('date'), (r) => r.txn.at),
      TableCol.text(tr('type'), (r) => r.txn.kind == SupplierTxnKind.purchase ? tr('purchase') : tr('payment')),
      TableCol.text(tr('method'), (r) => methodLabel(tr, r.txn.method), sortable: false),
      TableCol.text(tr('note'), (r) => r.txn.note, sortable: false),
      TableCol.text(tr('by'), (r) => r.txn.byName),
      TableCol.money(tr('purchase'), (r) => r.txn.kind == SupplierTxnKind.purchase ? r.txn.amountPaise : 0),
      TableCol.money(tr('payment'), (r) => r.txn.kind == SupplierTxnKind.payment ? r.txn.amountPaise : 0),
      TableCol.money(tr('balance'), (r) => r.balanceAfter),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: TileGrid(
            children: [
              StatTile(label: tr('payable'), value: formatRupees(supplier.balancePaise)),
              StatTile(label: tr('store'), value: store.name),
              if (supplier.gstin.isNotEmpty) StatTile(label: tr('gstin'), value: supplier.gstin),
              if (supplier.phone.isNotEmpty) StatTile(label: tr('phone'), value: supplier.phone),
            ],
          ),
        ),
        if (supplier.address.isNotEmpty) ...[
          const SizedBox(height: kGap),
          Muted('${tr('address')}: ${supplier.address}'),
        ],
        const SizedBox(height: kGap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _PurchaseDialog(repo: repo, supplier: supplier),
              ),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(tr('record_purchase')),
            ),
            OutlinedButton.icon(
              onPressed: () => _payment(context, tr, repo),
              icon: const Icon(Icons.payments_outlined),
              label: Text(tr('pay_supplier')),
            ),
            OutlinedButton.icon(
              onPressed: () => _edit(context, tr, repo),
              icon: const Icon(Icons.edit_outlined),
              label: Text(tr('edit')),
            ),
            OutlinedButton.icon(
              onPressed: () => _archive(context, tr, repo),
              icon: const Icon(Icons.archive_outlined),
              label: Text(tr('archive')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StoreStreamBuilder<List<SupplierTxn>>(
          stores: [store],
          cacheKey: 'supplier-txns-${supplier.id}',
          source: (r) => r.supplierTxns(supplier.id, limit: 2000),
          builder: (context, data) {
            final rows = _rows(data[store.id] ?? const [], supplier.balancePaise);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr('statement'), style: Theme.of(context).textTheme.titleMedium),
                    ),
                    TextButton.icon(
                      onPressed: rows.isEmpty
                          ? null
                          : () => downloadTextFile(
                                'supplier_statement.csv',
                                buildCsv([
                                  [tr('supplier'), supplier.name],
                                  [tr('payable'), csvMoney(supplier.balancePaise)],
                                  const [],
                                  ...tableCsvRows(columns, rows),
                                ]),
                              ),
                      icon: const Icon(Icons.download_outlined),
                      label: Text(tr('export_csv')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                AdminTable<_Row>(
                  columns: columns,
                  rows: rows,
                  sortColumn: 0,
                  ascending: false,
                  emptyMessage: tr('no_supplier_txns'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PurchaseLine {
  Product? product;
  final qty = TextEditingController();
  final cost = TextEditingController();
  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.repo, required this.supplier});
  final StoreRepository repo;
  final Supplier supplier;
  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _paid = TextEditingController();
  final _note = TextEditingController();
  final _lines = <_PurchaseLine>[];
  String _method = 'cash';
  bool _amountEdited = false;

  @override
  void dispose() {
    _amount.dispose();
    _paid.dispose();
    _note.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _linesTotal {
    var total = 0;
    for (final l in _lines) {
      final qty = parseQuantity(l.qty.text);
      final cost = parseRupees(l.cost.text);
      if (qty != null && cost != null) total += lineValue(cost, qty);
    }
    return total;
  }

  void _syncAmount() {
    if (_amountEdited) return;
    final total = _linesTotal;
    _amount.text = total == 0 ? '' : formatRupees(total, symbol: false).replaceAll(',', '');
  }

  void _submit(Tr tr) {
    if (!(_form.currentState?.validate() ?? false)) return;
    final lines = [
      for (final l in _lines)
        StockInLine(
          product: l.product!,
          qtyMilli: parseQuantity(l.qty.text)!,
          costPaise: parseRupees(l.cost.text)!,
        ),
    ];
    final method = _method == 'upi' ? PaymentMethod.upi : PaymentMethod.cash;
    final amount = parseRupees(_amount.text)!;
    final paid = _paid.text.trim().isEmpty ? 0 : parseRupees(_paid.text)!;
    final navigator = Navigator.of(context);
    runWrite(
      context,
      tr,
      () => widget.repo.recordSupplierPurchase(
        supplierId: widget.supplier.id,
        amountPaise: amount,
        paidPaise: paid,
        method: method,
        lines: lines,
        note: _note.text,
      ),
      done: tr('saved'),
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.select<SessionController, String>((s) => s.language);
    final v = Validators(tr);
    const decimal = TextInputType.numberWithOptions(decimal: true);
    return AlertDialog(
      scrollable: true,
      title: Text(tr('record_purchase')),
      content: SizedBox(
        width: 620,
        child: LiveBuilder<List<Product>>(
          cacheKey: 'purchase-products-${widget.repo.storeId}',
          create: () => widget.repo.products().take(1),
          builder: (context, products) => Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('stock_in_lines'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final line in _lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: DropdownButtonFormField<Product>(
                            initialValue: line.product,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: tr('product')),
                            items: [
                              for (final p in products)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(p.displayName(language), overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            validator: (p) {
                              if (p == null) return tr('required');
                              final repeats = _lines.where((l) => l.product?.id == p.id).length;
                              return repeats > 1 ? tr('duplicate_line') : null;
                            },
                            onChanged: (p) => setState(() {
                              line.product = p;
                              if (p != null && line.cost.text.isEmpty) {
                                line.cost.text =
                                    formatRupees(p.costPaise, symbol: false).replaceAll(',', '');
                              }
                              _syncAmount();
                            }),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            controller: line.qty,
                            decoration: InputDecoration(labelText: tr('quantity')),
                            keyboardType: decimal,
                            validator: v.quantity,
                            onChanged: (_) => setState(_syncAmount),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            controller: line.cost,
                            decoration: InputDecoration(labelText: tr('cost')),
                            keyboardType: decimal,
                            inputFormatters: [moneyInputFormatter],
                            validator: v.money,
                            onChanged: (_) => setState(_syncAmount),
                          ),
                        ),
                        IconButton(
                          tooltip: tr('remove_line'),
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _lines.remove(line);
                            line.dispose();
                            _syncAmount();
                          }),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _lines.length >= maxCartLines
                        ? null
                        : () => setState(() => _lines.add(_PurchaseLine())),
                    icon: const Icon(Icons.add),
                    label: Text(tr('add_line')),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amount,
                  decoration: InputDecoration(
                    labelText: tr('purchase_amount'),
                    helperText: tr('purchase_amount_hint'),
                    helperMaxLines: 2,
                  ),
                  keyboardType: decimal,
                  inputFormatters: [moneyInputFormatter],
                  validator: v.positiveMoney,
                  onChanged: (_) => _amountEdited = true,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _paid,
                  decoration: InputDecoration(labelText: tr('paid_now')),
                  keyboardType: decimal,
                  inputFormatters: [moneyInputFormatter],
                  validator: (text) {
                    final error = v.optionalMoney(text);
                    if (error != null) return error;
                    final paid = parseRupees(text ?? '') ?? 0;
                    final amount = parseRupees(_amount.text);
                    return amount != null && paid > amount ? tr('op_invalid_paid') : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('payment_method')),
                  items: [
                    DropdownMenuItem(value: 'cash', child: Text(tr('cash'))),
                    DropdownMenuItem(value: 'upi', child: Text(tr('upi'))),
                  ],
                  onChanged: (m) => setState(() => _method = m ?? 'cash'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  decoration: InputDecoration(labelText: tr('note')),
                  validator: v.maxLength(200),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('cancel'))),
        FilledButton(onPressed: () => _submit(tr), child: Text(tr('save'))),
      ],
    );
  }
}
