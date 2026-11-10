import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'suppliers_screen.dart';

const _lastSupplierKey = 'last_market_supplier';

/// Recent wholesale purchases, from every supplier.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final theme = Theme.of(context);
    return ManagerOnly(
      child: Scaffold(
        appBar: KiranaBar(title: tr('purchases')),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('purchases_add'),
          onPressed: () => push(context, const MarketPurchaseScreen()),
          icon: const Icon(Icons.add),
          label: Text(tr('market_purchase')),
        ),
        body: Live<List<Supplier>>(
          stream: (repo) => repo.suppliers(),
          builder: (context, suppliers) {
            final names = {for (final s in suppliers) s.id: s.name};
            return Live<List<SupplierTxn>>(
              stream: (repo) => repo.recentPurchases(),
              builder: (context, txns) {
                if (txns.isEmpty) {
                  return EmptyState(
                    icon: Icons.local_shipping_outlined,
                    message: tr('market_none'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: txns.length,
                  itemBuilder: (context, i) {
                    final t = txns[i];
                    final items = t.items.map((e) => e.name).toList();
                    return ListTile(
                      key: ValueKey('purchase_${t.id}'),
                      title: Text(names[t.supplierId] ?? tr('supplier')),
                      subtitle: Text(
                        [
                          formatDateTime(t.at, language),
                          if (items.isNotEmpty)
                            items.length <= 3
                                ? items.join(', ')
                                : '${items.take(3).join(', ')} · ${tr('market_items_count', {'count': '${items.length}'})}',
                          if (t.note.isNotEmpty) t.note,
                        ].join('\n'),
                      ),
                      trailing: Text(
                        formatRupees(t.amountPaise),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onTap: () => push(
                        context,
                        SupplierDetailScreen(supplierId: t.supplierId),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ItemDraft {
  final name = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

/// The morning trip to the wholesale market: where, how much, what was paid,
/// the auto fare, and, if there is time, what was bought.
class MarketPurchaseScreen extends StatefulWidget {
  const MarketPurchaseScreen({super.key});

  @override
  State<MarketPurchaseScreen> createState() => _MarketPurchaseScreenState();
}

class _MarketPurchaseScreenState extends State<MarketPurchaseScreen> {
  final _form = GlobalKey<FormState>();
  final _shopName = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController();
  final _transport = TextEditingController();
  final List<_ItemDraft> _items = [];
  String? _supplierId;
  bool _newShop = false;
  bool _paidInFull = true;
  bool _choseShop = false;
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _shopName.dispose();
    _total.dispose();
    _paid.dispose();
    _transport.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  int get _listSum =>
      _items.fold(0, (sum, i) => sum + parseRupeesOrZero(i.amount.text));

  int get _totalPaise =>
      _total.text.trim().isEmpty ? _listSum : parseRupeesOrZero(_total.text);

  int get _paidPaise =>
      _paidInFull ? _totalPaise : parseRupeesOrZero(_paid.text);

  /// Picks the shop used last time, once the supplier list arrives.
  void _defaultShop(List<Supplier> suppliers) {
    if (_choseShop) return;
    _choseShop = true;
    final last = context.session.prefs.getString(_lastSupplierKey);
    if (suppliers.isEmpty) {
      _newShop = true;
    } else {
      _supplierId = suppliers.any((s) => s.id == last)
          ? last
          : suppliers.first.id;
    }
  }

  void _addItem() => setState(() => _items.add(_ItemDraft()));

  void _removeItem(int index) =>
      setState(() => _items.removeAt(index).dispose());

  void _save() {
    final tr = context.trNow;
    if (!_form.currentState!.validate()) return;
    final total = _totalPaise;
    if (total <= 0) {
      showMessage(context, tr('market_total_required'));
      return;
    }
    final paid = _paidPaise;
    if (paid > total) {
      showMessage(context, tr('paid_exceeds_amount'));
      return;
    }
    if (!_newShop && _supplierId == null) return;
    final session = context.session;
    final String id;
    try {
      id = session.repository.recordMarketPurchase(
        supplierId: _newShop ? null : _supplierId,
        supplierName: _shopName.text,
        amountPaise: total,
        paidPaise: paid,
        method: _method,
        transportPaise: parseRupeesOrZero(_transport.text),
        items: [
          for (final i in _items)
            PurchaseLine(
              name: i.name.text,
              amountPaise: parseRupeesOrZero(i.amount.text),
            ),
        ],
      );
    } on InvalidOperation {
      showMessage(context, tr('error_generic'));
      return;
    }
    session.prefs.setString(_lastSupplierKey, id).ignore();
    showMessage(context, tr('market_saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final total = _totalPaise;
    final owed = total - _paidPaise;
    final listSum = _listSum;
    return ManagerOnly(
      child: Scaffold(
        appBar: KiranaBar(title: tr('market_purchase')),
        body: Form(
          key: _form,
          child: ScrollColumn(
            padding: const EdgeInsets.all(16),
            children: [
              Text(tr('market_bought_from'), style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              Live<List<Supplier>>(
                stream: (repo) => repo.suppliers(),
                builder: (context, suppliers) {
                  _defaultShop(suppliers);
                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in suppliers)
                        ChoiceChip(
                          key: ValueKey('market_shop_${s.id}'),
                          label: Text(s.name),
                          selected: !_newShop && _supplierId == s.id,
                          onSelected: (_) => setState(() {
                            _newShop = false;
                            _supplierId = s.id;
                          }),
                        ),
                      ChoiceChip(
                        key: const Key('market_new_shop'),
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(tr('market_new_shop')),
                        selected: _newShop,
                        onSelected: (_) => setState(() => _newShop = true),
                      ),
                    ],
                  );
                },
              ),
              if (_newShop) ...[
                const SizedBox(height: 10),
                TextFormField(
                  key: const Key('market_shop_name'),
                  controller: _shopName,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: tr('market_shop_name'),
                  ),
                  validator: V.required(tr),
                ),
              ],
              const SizedBox(height: 16),
              AmountField(
                key: const Key('market_total'),
                controller: _total,
                label: tr('market_total'),
                big: true,
                validator: V.amount(tr, optional: true),
                onChanged: (_) => setState(() {}),
              ),
              if (_total.text.trim().isEmpty && listSum > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: LabelValue(
                    tr('market_total_from_list'),
                    formatRupees(listSum),
                    strong: true,
                  ),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('market_paid_full'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr('market_paid_full')),
                value: _paidInFull,
                onChanged: (v) => setState(() => _paidInFull = v),
              ),
              if (!_paidInFull) ...[
                AmountField(
                  key: const Key('market_paid'),
                  controller: _paid,
                  label: tr('paid_now'),
                  validator: V.amount(tr, optional: true),
                  onChanged: (_) => setState(() {}),
                ),
                if (owed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr('market_still_owed', {'amount': formatRupees(owed)}),
                      style: const TextStyle(
                        color: KiranaColors.dues,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
              if (_paidPaise > 0) ...[
                const SizedBox(height: 10),
                MethodPicker(
                  value: _method,
                  onChanged: (m) => setState(() => _method = m),
                ),
              ],
              const SizedBox(height: 16),
              AmountField(
                key: const Key('market_transport'),
                controller: _transport,
                label: tr('market_transport'),
                validator: V.amount(tr, optional: true),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  tr('market_transport_hint'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              SectionTitle(tr('market_list')),
              for (var i = 0; i < _items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          key: ValueKey('market_item_$i'),
                          controller: _items[i].name,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            labelText: tr('market_item'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: AmountField(
                          key: ValueKey('market_item_amount_$i'),
                          controller: _items[i].amount,
                          label: tr('amount'),
                          validator: V.amount(tr, optional: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('market_remove_item'),
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeItem(i),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('market_add_item'),
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: Text(tr('market_add_item')),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAction(
          child: FilledButton(
            key: const Key('market_save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _save,
            child: Text(
              total > 0 ? '${tr('save')} · ${formatRupees(total)}' : tr('save'),
            ),
          ),
        ),
      ),
    );
  }
}
