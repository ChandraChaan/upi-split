import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/dates.dart';
import '../utils/platform.dart';
import '../utils/rollups.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';

enum _Report { profitLoss, paymentModes, collections, productSales, duesAgeing, storeComparison }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  RangePreset _preset = RangePreset.thisMonth;
  DateRange _range = presetRange(RangePreset.thisMonth, DateTime.now());
  _Report _report = _Report.profitLoss;

  String _label(Tr tr, _Report r) => switch (r) {
        _Report.profitLoss => tr('report_profit_loss'),
        _Report.paymentModes => tr('report_payment_modes'),
        _Report.collections => tr('report_collections'),
        _Report.productSales => tr('report_product_sales'),
        _Report.duesAgeing => tr('report_dues_ageing'),
        _Report.storeComparison => tr('report_store_comparison'),
      };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    final current = _report == _Report.storeComparison && stores.length < 2
        ? _Report.profitLoss
        : _report;
    return PageBody(
      title: tr('reports'),
      filters: [
        if (current != _Report.duesAgeing)
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
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _Report.values)
                if (r != _Report.storeComparison || stores.length > 1)
                  ChoiceChip(
                    label: Text(_label(tr, r)),
                    selected: current == r,
                    onSelected: (_) => setState(() => _report = r),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          switch (current) {
            _Report.duesAgeing => _DuesAgeing(stores: stores),
            final report => StoreStreamBuilder<List<DayRollup>>(
                stores: stores,
                cacheKey: 'report-days-${_range.cacheKey}',
                source: (repo) => repo.days(from: _range.fromKey, to: _range.toKey),
                builder: (context, days) => switch (report) {
                  _Report.profitLoss => _ProfitLoss(days: days, range: _range),
                  _Report.paymentModes => _PaymentModes(days: days, range: _range),
                  _Report.collections => _Collections(days: days, range: _range),
                  _Report.productSales => _ProductSales(stores: stores, days: days, range: _range),
                  _ => _StoreComparison(stores: stores, days: days, range: _range),
                },
              ),
          },
        ],
      ),
    );
  }
}

/// Export button above a report table.
class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.fileName, required this.csvRows});
  final String fileName;
  final List<List<Object?>> Function() csvRows;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: () => downloadTextFile('$fileName.csv', buildCsv(csvRows())),
        icon: const Icon(Icons.download_outlined),
        label: Text(tr('export_csv')),
      ),
    );
  }
}

typedef _DayRow = ({String day, PeriodSummary summary});

List<_DayRow> _dayRows(Map<String, List<DayRollup>> days) {
  final daily = dailySummaries(days.values);
  final keys = daily.keys.toList()..sort();
  return [for (final k in keys) (day: k, summary: daily[k]!)];
}

PeriodSummary _totalOf(Map<String, List<DayRollup>> days) =>
    PeriodSummary.of(days.values.expand((d) => d));

class _ProfitLoss extends StatelessWidget {
  const _ProfitLoss({required this.days, required this.range});
  final Map<String, List<DayRollup>> days;
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final rows = _dayRows(days);
    final total = _totalOf(days);
    final totalRow = (day: tr('total'), summary: total);
    final columns = <TableCol<_DayRow>>[
      TableCol.text(tr('date'), (r) => r.day == tr('total') ? r.day : formatDayKey(r.day)),
      TableCol.money(tr('sales'), (r) => r.summary.salesPaise),
      TableCol.money(tr('cogs'), (r) => r.summary.cogsPaise),
      TableCol.money(tr('gross_profit'), (r) => r.summary.grossProfitPaise),
      TableCol.money(tr('expenses'), (r) => r.summary.expensePaise),
      TableCol.money(tr('net_profit'), (r) => r.summary.netProfitPaise),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(
          fileName: 'profit_loss_${range.cacheKey}',
          csvRows: () => tableCsvRows(columns, [...rows, totalRow]),
        ),
        AdminTable<_DayRow>(
          columns: columns,
          rows: rows,
          totalRow: rows.isEmpty ? null : totalRow,
          emptyMessage: tr('no_sales_period'),
        ),
      ],
    );
  }
}

typedef _ModeRow = ({String mode, int sales, int collected, int? net});

class _PaymentModes extends StatelessWidget {
  const _PaymentModes({required this.days, required this.range});
  final Map<String, List<DayRollup>> days;
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final s = _totalOf(days);
    final rows = <_ModeRow>[
      (mode: tr('cash'), sales: s.cashSalesPaise, collected: s.collectionCashPaise, net: s.netCashPaise),
      (mode: tr('upi'), sales: s.upiSalesPaise, collected: s.collectionUpiPaise, net: s.netUpiPaise),
      (mode: tr('credit'), sales: s.creditSalesPaise, collected: 0, net: null),
    ];
    String share(int part) =>
        s.salesPaise == 0 ? '-' : '${(part * 100 / s.salesPaise).toStringAsFixed(1)}%';
    final columns = <TableCol<_ModeRow>>[
      TableCol.text(tr('payment_method'), (r) => r.mode),
      TableCol.money(tr('sales'), (r) => r.sales),
      TableCol.text(tr('share_percent'), (r) => share(r.sales), sortable: false),
      TableCol.money(tr('collections'), (r) => r.collected),
      TableCol(
        tr('net_after_payouts'),
        (r) => Text(r.net == null ? '-' : formatRupees(r.net!)),
        numeric: true,
        csv: (r) => r.net == null ? '' : csvMoney(r.net!),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(
          fileName: 'payment_modes_${range.cacheKey}',
          csvRows: () => tableCsvRows(columns, rows),
        ),
        AdminTable<_ModeRow>(
          columns: columns,
          rows: s.salesPaise == 0 && s.collectionCashPaise == 0 && s.collectionUpiPaise == 0
              ? const []
              : rows,
          emptyMessage: tr('no_sales_period'),
        ),
      ],
    );
  }
}

class _Collections extends StatelessWidget {
  const _Collections({required this.days, required this.range});
  final Map<String, List<DayRollup>> days;
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final rows = _dayRows(days)
        .where((r) => r.summary.collectionCashPaise != 0 || r.summary.collectionUpiPaise != 0)
        .toList();
    final totalRow = (day: tr('total'), summary: _totalOf(days));
    final columns = <TableCol<_DayRow>>[
      TableCol.text(tr('date'), (r) => r.day == tr('total') ? r.day : formatDayKey(r.day)),
      TableCol.money(tr('cash'), (r) => r.summary.collectionCashPaise),
      TableCol.money(tr('upi'), (r) => r.summary.collectionUpiPaise),
      TableCol.money(tr('total'), (r) => r.summary.collectionCashPaise + r.summary.collectionUpiPaise),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(
          fileName: 'collections_${range.cacheKey}',
          csvRows: () => tableCsvRows(columns, [...rows, totalRow]),
        ),
        AdminTable<_DayRow>(
          columns: columns,
          rows: rows,
          totalRow: rows.isEmpty ? null : totalRow,
          emptyMessage: tr('no_collections_period'),
        ),
      ],
    );
  }
}

class _ProductSales extends StatelessWidget {
  const _ProductSales({required this.stores, required this.days, required this.range});
  final List<Store> stores;
  final Map<String, List<DayRollup>> days;
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.select<SessionController, String>((s) => s.language);
    return StoreStreamBuilder<List<Product>>(
      stores: stores,
      cacheKey: 'report-products',
      source: (repo) => repo.products(includeInactive: true),
      builder: (context, products) {
        final rows = aggregateProductSales(days, products, language, unknownName: tr('unknown_product'));
        String margin(NamedProductSales p) =>
            p.marginPercent == null ? '-' : '${p.marginPercent!.toStringAsFixed(1)}%';
        final columns = <TableCol<NamedProductSales>>[
          TableCol.text(tr('product'), (p) => p.name),
          TableCol.qty(tr('quantity'), (p) => p.qtyMilli),
          TableCol.money(tr('sales'), (p) => p.revenuePaise),
          TableCol.money(tr('cogs'), (p) => p.cogsPaise),
          TableCol.money(tr('profit'), (p) => p.profitPaise),
          TableCol(
            tr('margin'),
            (p) => Text(margin(p)),
            sortKey: (p) => p.marginPercent,
            numeric: true,
            csv: margin,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportHeader(
              fileName: 'product_sales_${range.cacheKey}',
              csvRows: () => tableCsvRows(columns, rows),
            ),
            AdminTable<NamedProductSales>(
              columns: columns,
              rows: rows,
              sortColumn: 2,
              ascending: false,
              emptyMessage: tr('no_sales_period'),
            ),
          ],
        );
      },
    );
  }
}

class _DuesAgeing extends StatelessWidget {
  const _DuesAgeing({required this.stores});
  final List<Store> stores;

  String _bucketLabel(Tr tr, AgeBucket b) => switch (b) {
        AgeBucket.noDueDate => tr('age_no_due_date'),
        AgeBucket.notYetDue => tr('age_not_yet_due'),
        AgeBucket.days1to30 => tr('age_1_30'),
        AgeBucket.days31to60 => tr('age_31_60'),
        AgeBucket.days61to90 => tr('age_61_90'),
        AgeBucket.over90 => tr('age_over_90'),
      };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final now = DateTime.now();
    return StoreStreamBuilder<List<Customer>>(
      stores: stores,
      cacheKey: 'report-customers',
      source: (repo) => repo.customers(),
      builder: (context, byStore) {
        final all = flatten(stores, byStore).where((r) => r.item.hasDues).toList();
        final totals = duesAgeing(all.map((e) => e.item), now);
        final columns = <TableCol<StoreItem<Customer>>>[
          TableCol.text(tr('customer'), (r) => r.item.name),
          TableCol.text(tr('phone'), (r) => r.item.phone),
          if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
          TableCol.money(tr('outstanding'), (r) => r.item.balancePaise),
          TableCol.date(tr('due_date'), (r) => r.item.dueDate),
          TableCol(
            tr('days_overdue'),
            (r) {
              final days = daysPastDue(r.item, now);
              return Text(days == null || days <= 0 ? '-' : '$days');
            },
            sortKey: (r) => daysPastDue(r.item, now),
            numeric: true,
            csv: (r) {
              final days = daysPastDue(r.item, now);
              return days == null || days <= 0 ? '' : '$days';
            },
          ),
          TableCol.text(tr('age_bucket'), (r) => _bucketLabel(tr, ageBucket(r.item, now))),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              child: TileGrid(
                children: [
                  for (final e in totals.entries)
                    StatTile(label: _bucketLabel(tr, e.key), value: formatRupees(e.value)),
                ],
              ),
            ),
            _ReportHeader(
              fileName: 'dues_ageing_${dayKey(now)}',
              csvRows: () => tableCsvRows(columns, all),
            ),
            AdminTable<StoreItem<Customer>>(
              columns: columns,
              rows: all,
              sortColumn: columns.indexWhere((c) => c.label == tr('outstanding')),
              ascending: false,
              emptyMessage: tr('no_dues'),
            ),
          ],
        );
      },
    );
  }
}

typedef _StoreRow = ({Store store, PeriodSummary summary, int outstanding});

class _StoreComparison extends StatelessWidget {
  const _StoreComparison({required this.stores, required this.days, required this.range});
  final List<Store> stores;
  final Map<String, List<DayRollup>> days;
  final DateRange range;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return StoreStreamBuilder<List<Customer>>(
      stores: stores,
      cacheKey: 'report-customers',
      source: (repo) => repo.customers(),
      builder: (context, customers) {
        final rows = <_StoreRow>[
          for (final s in stores)
            (
              store: s,
              summary: PeriodSummary.of(days[s.id] ?? const []),
              outstanding: totalOutstanding(customers[s.id] ?? const []),
            ),
        ];
        final columns = <TableCol<_StoreRow>>[
          TableCol.text(tr('store'), (r) => r.store.name),
          TableCol.money(tr('sales'), (r) => r.summary.salesPaise),
          TableCol.text(tr('bills'), (r) => '${r.summary.billCount}', sortable: false),
          TableCol.money(tr('average_bill'), (r) => r.summary.averageBillPaise),
          TableCol.money(tr('gross_profit'), (r) => r.summary.grossProfitPaise),
          TableCol.money(tr('expenses'), (r) => r.summary.expensePaise),
          TableCol.money(tr('net_profit'), (r) => r.summary.netProfitPaise),
          TableCol.money(
            tr('collections'),
            (r) => r.summary.collectionCashPaise + r.summary.collectionUpiPaise,
          ),
          TableCol.money(tr('outstanding'), (r) => r.outstanding),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReportHeader(
              fileName: 'store_comparison_${range.cacheKey}',
              csvRows: () => tableCsvRows(columns, rows),
            ),
            AdminTable<_StoreRow>(
              columns: columns,
              rows: rows,
              sortColumn: 1,
              ascending: false,
              emptyMessage: tr('no_data'),
            ),
          ],
        );
      },
    );
  }
}
