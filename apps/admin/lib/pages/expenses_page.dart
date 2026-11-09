import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/dates.dart';
import '../utils/platform.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  RangePreset _preset = RangePreset.thisMonth;
  DateRange _range = presetRange(RangePreset.thisMonth, DateTime.now());

  Future<void> _add(Tr tr, List<Store> stores, List<String> categories) async {
    final v = Validators(tr);
    final presets = [
      tr('expense_rent'),
      tr('expense_electricity'),
      tr('expense_salary'),
      tr('expense_transport'),
      tr('expense_packing'),
      tr('expense_other'),
    ];
    final now = DateTime.now();
    final values = await showFormDialog(
      context,
      title: tr('add_expense'),
      specs: [
        ChoiceSpec('store', tr('store'), storeOptions(stores),
            initial: stores.length == 1 ? stores.first.id : null),
        TextSpec('category', tr('category'),
            suggestions: {...categories, ...presets}.toList(),
            validator: v.maxLength(60, isRequired: true)),
        TextSpec('amount', tr('amount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.positiveMoney,
            formatters: [moneyInputFormatter]),
        ChoiceSpec('method', tr('payment_method'), {'cash': tr('cash'), 'upi': tr('upi')},
            initial: 'cash'),
        DateSpec('date', tr('expense_date'),
            initial: now, first: DateTime(now.year - 2), last: now),
        TextSpec('note', tr('note'), validator: v.maxLength(200)),
      ],
    );
    if (values == null || !mounted) return;
    final date = values.date('date');
    final repo = context.read<SessionController>().repositoryFor(values.choice('store')!);
    runWrite(
      context,
      tr,
      () => repo.addExpense(
        category: values.text('category'),
        amountPaise: values.money('amount'),
        method: values.choice('method') == 'upi' ? PaymentMethod.upi : PaymentMethod.cash,
        note: values.text('note'),
        at: DateTime(date.year, date.month, date.day, now.hour, now.minute, now.second),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _void(Tr tr, StoreItem<Expense> row) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('void_expense'),
      message: tr('void_expense_body', {
        'category': row.item.category,
        'amount': formatRupees(row.item.amountPaise),
      }),
      confirmLabel: tr('void_action'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final repo = context.read<SessionController>().repositoryFor(row.store.id);
    runWrite(context, tr, () => repo.voidExpense(row.item), done: tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    return StoreStreamBuilder<List<Expense>>(
      stores: stores,
      cacheKey: 'expenses-${_range.cacheKey}',
      source: (repo) => repo.expenses(from: _range.from, to: _range.toExclusive),
      builder: (context, byStore) {
        final rows = flatten(stores, byStore);
        final live = rows.where((r) => !r.item.voided).toList();
        final total = live.fold<int>(0, (t, r) => t + r.item.amountPaise);
        final byCategory = <String, int>{};
        for (final r in live) {
          final key = r.item.category.trim();
          byCategory[key] = (byCategory[key] ?? 0) + r.item.amountPaise;
        }
        final categoryRows = byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final columns = <TableCol<StoreItem<Expense>>>[
          TableCol.dateTime(tr('date'), (r) => r.item.at),
          if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
          TableCol.text(tr('category'), (r) => r.item.category),
          TableCol.money(tr('amount'), (r) => r.item.amountPaise),
          TableCol.text(tr('method'), (r) => methodLabel(tr, r.item.method)),
          TableCol.text(tr('note'), (r) => r.item.note, sortable: false),
          TableCol.text(tr('by'), (r) => r.item.byName),
          TableCol(
            tr('status'),
            (r) => r.item.voided
                ? StatusChip(label: tr('voided'), color: KiranaColors.dues, icon: Icons.block)
                : TextButton(onPressed: () => _void(tr, r), child: Text(tr('void_action'))),
            csv: (r) => r.item.voided ? tr('voided') : '',
          ),
        ];
        return PageBody(
          title: tr('expenses'),
          actions: [
            FilledButton.icon(
              onPressed: () => _add(tr, stores, categoryRows.map((e) => e.key).toList()),
              icon: const Icon(Icons.add),
              label: Text(tr('add_expense')),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => downloadTextFile(
                        'expenses_${_range.cacheKey}.csv',
                        buildCsv(tableCsvRows(columns, rows)),
                      ),
              icon: const Icon(Icons.download_outlined),
              label: Text(tr('export_csv')),
            ),
          ],
          filters: [
            DateRangeFilter(
              preset: _preset,
              range: _range,
              onChanged: (p, r) => setState(() {
                _preset = p;
                _range = r;
              }),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: tr('totals_by_category'),
                child: live.isEmpty
                    ? Muted(tr('no_expenses_period'))
                    : TileGrid(
                        children: [
                          StatTile(label: tr('total'), value: formatRupees(total)),
                          for (final e in categoryRows)
                            StatTile(label: e.key, value: formatRupees(e.value)),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              AdminTable<StoreItem<Expense>>(
                columns: columns,
                rows: rows,
                sortColumn: 0,
                ascending: false,
                emptyMessage: tr('no_expenses_period'),
              ),
            ],
          ),
        );
      },
    );
  }
}
