import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/dates.dart';
import '../utils/rollups.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    final now = DateTime.now();
    final today = dateOnly(now);
    final trendStart = DateTime(today.year, today.month, today.day - 29);
    final monthStart = DateTime(today.year, today.month);
    final from = trendStart.isBefore(monthStart) ? trendStart : monthStart;
    final range = DateRange(from, today);

    return PageBody(
      title: tr('dashboard'),
      child: StoreStreamBuilder<List<DayRollup>>(
        stores: stores,
        cacheKey: 'dash-days-${range.cacheKey}',
        source: (repo) => repo.days(from: range.fromKey, to: range.toKey),
        builder: (context, days) => StoreStreamBuilder<List<Customer>>(
          stores: stores,
          cacheKey: 'dash-customers',
          source: (repo) => repo.customers(),
          builder: (context, customers) => StoreStreamBuilder<List<Product>>(
            stores: stores,
            cacheKey: 'dash-products',
            source: (repo) => repo.products(includeInactive: true),
            builder: (context, products) => _DashboardBody(
              stores: stores,
              today: today,
              trendRange: DateRange(trendStart, today),
              monthStart: monthStart,
              days: days,
              customers: customers,
              products: products,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.stores,
    required this.today,
    required this.trendRange,
    required this.monthStart,
    required this.days,
    required this.customers,
    required this.products,
  });

  final List<Store> stores;
  final DateTime today;
  final DateRange trendRange;
  final DateTime monthStart;
  final Map<String, List<DayRollup>> days;
  final Map<String, List<Customer>> customers;
  final Map<String, List<Product>> products;

  List<Widget> _periodTiles(Tr tr, PeriodSummary s) => [
        StatTile(label: tr('sales'), value: formatRupees(s.salesPaise)),
        StatTile(label: tr('gross_profit'), value: formatRupees(s.grossProfitPaise)),
        StatTile(label: tr('net_profit'), value: formatRupees(s.netProfitPaise)),
        StatTile(label: tr('cash'), value: formatRupees(s.cashSalesPaise)),
        StatTile(label: tr('upi'), value: formatRupees(s.upiSalesPaise)),
        StatTile(label: tr('credit'), value: formatRupees(s.creditSalesPaise)),
        StatTile(
          label: tr('collections'),
          value: formatRupees(s.collectionCashPaise + s.collectionUpiPaise),
        ),
        StatTile(label: tr('expenses'), value: formatRupees(s.expensePaise)),
      ];

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.select<SessionController, String>((s) => s.language);
    final todayKey = dayKey(today);
    final monthKey = dayKey(monthStart);

    final allDays = days.values.expand((d) => d).toList();
    final todaySummary = PeriodSummary.of(allDays.where((d) => d.dayKey == todayKey));
    final monthDays = {
      for (final e in days.entries)
        e.key: e.value.where((d) => d.dayKey.compareTo(monthKey) >= 0).toList(),
    };
    final monthSummary = PeriodSummary.of(monthDays.values.expand((d) => d));

    final daily = dailySummaries(days.values);
    final trendKeys = trendRange.dayKeys;
    int metric(String key, int Function(PeriodSummary s) f) =>
        daily[key] == null ? 0 : f(daily[key]!);
    final salesTrend = [for (final k in trendKeys) metric(k, (s) => s.salesPaise)];
    final profitTrend = [for (final k in trendKeys) metric(k, (s) => s.netProfitPaise)];
    final dayLabels = [for (final k in trendKeys) formatDayKey(k).substring(0, 5)];

    final customerRows = flatten(stores, customers);
    final productRows = flatten(stores, products);
    final outstanding = totalOutstanding(customerRows.map((e) => e.item));
    final inventory = inventoryValue(productRows.map((e) => e.item));
    final lowStock = productRows.where((e) => e.item.active && e.item.isLowStock).toList()
      ..sort((a, b) => (a.item.stockMilli - a.item.lowStockMilli)
          .compareTo(b.item.stockMilli - b.item.lowStockMilli));
    final topDues = customerRows.where((e) => e.item.hasDues).toList()
      ..sort((a, b) => b.item.balancePaise.compareTo(a.item.balancePaise));

    final topProducts = aggregateProductSales(monthDays, products, language, limit: 8);
    final byStore = stores
        .map((s) => RankedValue(s.name, PeriodSummary.of(monthDays[s.id] ?? const []).salesPaise))
        .toList()
      ..sort((a, b) => b.paise.compareTo(a.paise));
    final paymentParts = [
      MixPart(tr('cash'), chartSlot1, monthSummary.cashSalesPaise),
      MixPart(tr('upi'), chartSlot2, monthSummary.upiSalesPaise),
      MixPart(tr('credit'), chartSlot3, monthSummary.creditSalesPaise),
    ];

    final noData = EmptyState(message: tr('no_sales_period'), icon: Icons.bar_chart);
    final hasTrend = salesTrend.any((v) => v != 0) || profitTrend.any((v) => v != 0);
    final hasMix = monthSummary.salesPaise > 0;

    return LayoutBuilder(builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 900;
      Widget pair(Widget a, Widget b) => twoColumns
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [a, const SizedBox(height: 16), b],
            );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(title: tr('today'), child: TileGrid(children: _periodTiles(tr, todaySummary))),
          const SizedBox(height: 16),
          SectionCard(
            title: tr('this_month'),
            child: TileGrid(children: _periodTiles(tr, monthSummary)),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: TileGrid(
              children: [
                StatTile(label: tr('total_outstanding'), value: formatRupees(outstanding)),
                StatTile(label: tr('inventory_value'), value: formatRupees(inventory)),
                StatTile(
                  label: tr('low_stock_count'),
                  value: '${lowStock.length}',
                  icon: lowStock.isEmpty ? null : Icons.warning_amber_rounded,
                  color: KiranaColors.warning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ChartCard(
            title: tr('trend_30_days'),
            chart: hasTrend
                ? TrendChart(dayLabels: dayLabels, series: [
                    TrendSeries(tr('sales'), chartSlot1, salesTrend),
                    TrendSeries(tr('net_profit'), chartSlot2, profitTrend),
                  ])
                : noData,
            table: ChartTable(rows: [
              [tr('date'), tr('sales'), tr('net_profit')],
              for (var i = trendKeys.length - 1; i >= 0; i--)
                [dayLabels[i], formatRupees(salesTrend[i]), formatRupees(profitTrend[i])],
            ]),
          ),
          const SizedBox(height: 16),
          pair(
            ChartCard(
              title: tr('payment_mix_month'),
              chart: hasMix ? SegmentedMix(parts: paymentParts) : noData,
              table: ChartTable(rows: [
                for (final p in paymentParts) [p.label, formatRupees(p.paise)],
              ]),
            ),
            stores.length > 1
                ? ChartCard(
                    title: tr('sales_by_store_month'),
                    chart: hasMix ? RankedBars(items: byStore) : noData,
                    table: ChartTable(rows: [
                      for (final s in byStore) [s.label, formatRupees(s.paise)],
                    ]),
                  )
                : _TopProducts(items: topProducts, emptyView: noData),
          ),
          if (stores.length > 1) ...[
            const SizedBox(height: 16),
            _TopProducts(items: topProducts, emptyView: noData),
          ],
          const SizedBox(height: 16),
          pair(
            SectionCard(
              title: tr('top_dues'),
              child: topDues.isEmpty
                  ? EmptyState(message: tr('no_dues'), icon: Icons.check_circle_outline)
                  : Column(
                      children: [
                        for (final row in topDues.take(8))
                          _ListRow(
                            title: row.item.name,
                            subtitle: stores.length > 1 ? row.store.name : row.item.phone,
                            trailing: formatRupees(row.item.balancePaise),
                            onTap: () => context.go('/customers/${row.store.id}/${row.item.id}'),
                          ),
                      ],
                    ),
            ),
            SectionCard(
              title: tr('low_stock'),
              child: lowStock.isEmpty
                  ? EmptyState(message: tr('no_low_stock'), icon: Icons.check_circle_outline)
                  : Column(
                      children: [
                        for (final row in lowStock.take(8))
                          _ListRow(
                            title: row.item.displayName(language),
                            subtitle: stores.length > 1 ? row.store.name : row.item.category,
                            trailing:
                                '${formatQuantity(row.item.stockMilli)} ${unitLabel(tr, row.item.unit)}',
                            onTap: () => context.go('/products/${row.store.id}/${row.item.id}'),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      );
    });
  }
}

class _TopProducts extends StatelessWidget {
  const _TopProducts({required this.items, required this.emptyView});
  final List<NamedProductSales> items;
  final Widget emptyView;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return ChartCard(
      title: tr('top_products_month'),
      chart: items.isEmpty
          ? emptyView
          : RankedBars(items: [for (final p in items) RankedValue(p.name, p.revenuePaise)]),
      table: ChartTable(rows: [
        [tr('product'), tr('quantity'), tr('sales')],
        for (final p in items) [p.name, formatQuantity(p.qtyMilli), formatRupees(p.revenuePaise)],
      ]),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.title, required this.subtitle, required this.trailing, this.onTap});
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: onTap,
        title: Text(title),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Text(trailing),
      );
}
