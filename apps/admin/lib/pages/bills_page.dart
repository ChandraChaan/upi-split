import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/dates.dart';
import '../utils/platform.dart';
import '../utils/receipt_html.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

const int _billQueryLimit = 500;

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});
  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  RangePreset _preset = RangePreset.last7;
  DateRange _range = presetRange(RangePreset.last7, DateTime.now());
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    return PageBody(
      title: tr('bills'),
      filters: [
        DateRangeFilter(
          preset: _preset,
          range: _range,
          onChanged: (p, r) => setState(() {
            _preset = p;
            _range = r;
          }),
        ),
        SearchField(
          hint: tr('search_bills'),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      ],
      child: StoreStreamBuilder<List<Bill>>(
        stores: stores,
        cacheKey: 'bills-${_range.cacheKey}',
        source: (repo) =>
            repo.bills(from: _range.from, to: _range.toExclusive, limit: _billQueryLimit),
        builder: (context, byStore) {
          final truncated = byStore.values.any((b) => b.length >= _billQueryLimit);
          final all = flatten(stores, byStore);
          final rows = all.where((r) {
            if (_query.isEmpty) return true;
            return r.item.number.toLowerCase().contains(_query) ||
                r.item.customerName.toLowerCase().contains(_query);
          }).toList();
          final columns = <TableCol<StoreItem<Bill>>>[
            TableCol.text(tr('bill_number'), (r) => r.item.number),
            TableCol.dateTime(tr('date'), (r) => r.item.at),
            if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
            TableCol.text(tr('customer'), (r) => r.item.customerName),
            TableCol.text(tr('items'), (r) => '${r.item.items.length}', sortable: false),
            TableCol.money(tr('total'), (r) => r.item.totalPaise),
            TableCol.money(tr('cash'), (r) => r.item.cashPaise),
            TableCol.money(tr('upi'), (r) => r.item.upiPaise),
            TableCol.money(tr('credit'), (r) => r.item.creditPaise),
            TableCol.text(tr('by'), (r) => r.item.byName),
            TableCol(
              tr('status'),
              (r) => r.item.voided
                  ? StatusChip(label: tr('voided'), color: KiranaColors.dues, icon: Icons.block)
                  : const Text('-'),
              csv: (r) => r.item.voided ? tr('voided') : '',
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Muted(tr('bills_summary', {
                    'count': '${all.where((r) => !r.item.voided).length}',
                    'amount': formatRupees(all
                        .where((r) => !r.item.voided)
                        .fold<int>(0, (t, r) => t + r.item.totalPaise)),
                  })),
                  TextButton.icon(
                    onPressed: rows.isEmpty
                        ? null
                        : () => downloadTextFile(
                              'bills_${_range.cacheKey}.csv',
                              buildCsv(tableCsvRows(columns, rows)),
                            ),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(tr('export_csv')),
                  ),
                ],
              ),
              if (truncated) Muted(tr('bills_truncated', {'limit': '$_billQueryLimit'})),
              const SizedBox(height: 8),
              AdminTable<StoreItem<Bill>>(
                columns: columns,
                rows: rows,
                sortColumn: 1,
                ascending: false,
                emptyMessage: all.isEmpty ? tr('no_bills') : tr('no_matches'),
                onTap: (r) => context.go('/bills/${r.store.id}/${r.item.id}'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class BillDetailPage extends StatefulWidget {
  const BillDetailPage({super.key, required this.storeId, required this.billId});
  final String storeId;
  final String billId;
  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  String? _receiptLanguage;

  Future<void> _void(Tr tr, StoreRepository repo, Bill bill) async {
    final values = await showFormDialog(
      context,
      title: tr('void_bill'),
      description: tr('void_bill_hint'),
      submitLabel: tr('void_action'),
      specs: [
        TextSpec('reason', tr('reason'), validator: Validators(tr).maxLength(200, isRequired: true)),
      ],
    );
    if (values == null || !mounted) return;
    runWrite(context, tr, () => repo.voidBill(bill, reason: values.text('reason')), done: tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final store = accessibleStore(context, widget.storeId);
    void back() => context.go('/bills');
    if (store == null) {
      return PageBody(title: tr('bill'), onBack: back, child: NotFoundBody(onBack: back));
    }
    final language = _receiptLanguage ?? session.language;
    return StoreStreamBuilder<Bill?>(
      stores: [store],
      cacheKey: 'bill-${widget.billId}',
      source: (repo) => repo.bill(widget.billId),
      builder: (context, data) {
        final bill = data[store.id];
        if (bill == null) {
          return PageBody(title: tr('bill'), onBack: back, child: NotFoundBody(onBack: back));
        }
        final repo = session.repositoryFor(store.id);
        return PageBody(
          title: '${tr('bill')} ${bill.number}',
          onBack: back,
          actions: [
            FilledButton.icon(
              onPressed: () => printHtml(
                receiptHtml(tr: Tr(language), language: language, store: store, bill: bill),
              ),
              icon: const Icon(Icons.print_outlined),
              label: Text(tr('print')),
            ),
            if (!bill.voided)
              OutlinedButton.icon(
                onPressed: () => _void(tr, repo, bill),
                icon: const Icon(Icons.block),
                label: Text(tr('void_bill')),
              ),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'te', label: Text(tr('telugu'))),
                ButtonSegment(value: 'en', label: Text(tr('english'))),
              ],
              selected: {language},
              onSelectionChanged: (s) => setState(() => _receiptLanguage = s.first),
            ),
          ],
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _Receipt(store: store, bill: bill, language: language),
            ),
          ),
        );
      },
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.store, required this.bill, required this.language});
  final Store store;
  final Bill bill;
  final String language;

  Widget _line(String label, String value, {TextStyle? style}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: style)),
            const SizedBox(width: 12),
            Text(value, style: style),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Follows the receipt's language, which can differ from the app's.
    final tr = Tr(language);
    final theme = Theme.of(context);
    final strong = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(store.name, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
            if (store.address.isNotEmpty) Text(store.address, textAlign: TextAlign.center),
            if (store.phone.isNotEmpty)
              Text('${tr('phone')}: ${store.phone}', textAlign: TextAlign.center),
            if (store.gstin.isNotEmpty) Text('GSTIN: ${store.gstin}', textAlign: TextAlign.center),
            const Divider(height: 24),
            Text('${tr('bill')}: ${bill.number}'),
            Text(formatDateTime(bill.at)),
            if (bill.customerName.isNotEmpty) Text('${tr('customer')}: ${bill.customerName}'),
            if (bill.voided) ...[
              const SizedBox(height: 8),
              StatusChip(
                label: '${tr('voided')}: ${bill.voidReason}',
                color: KiranaColors.dues,
                icon: Icons.block,
              ),
            ],
            const Divider(height: 24),
            for (final item in bill.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.displayName(language)),
                          Muted('${formatQuantity(item.qtyMilli)} x ${formatRupees(item.pricePaise)}'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(formatRupees(item.totalPaise)),
                  ],
                ),
              ),
            const Divider(height: 24),
            if (bill.discountPaise > 0) ...[
              _line(tr('subtotal'), formatRupees(bill.subtotalPaise)),
              _line(tr('discount'), formatRupees(bill.discountPaise)),
            ],
            _line(tr('total'), formatRupees(bill.totalPaise), style: strong),
            const SizedBox(height: 4),
            if (bill.cashPaise > 0) _line(tr('cash'), formatRupees(bill.cashPaise)),
            if (bill.upiPaise > 0) _line(tr('upi'), formatRupees(bill.upiPaise)),
            if (bill.creditPaise > 0) _line(tr('credit'), formatRupees(bill.creditPaise)),
            if (store.receiptFooter.isNotEmpty) ...[
              const Divider(height: 24),
              Text(store.receiptFooter, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
