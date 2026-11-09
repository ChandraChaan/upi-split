import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

enum _Period { today, yesterday, week, month, custom }

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ManagerOnly(child: _Reports());
}

class _Reports extends StatefulWidget {
  const _Reports();

  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  _Period _period = _Period.today;
  DateTimeRange? _custom;

  (DateTime, DateTime) _range() {
    final today = startOfDay(DateTime.now());
    return switch (_period) {
      _Period.today => (today, today),
      _Period.yesterday => () {
        final y = DateTime(today.year, today.month, today.day - 1);
        return (y, y);
      }(),
      _Period.week => (
        DateTime(today.year, today.month, today.day - (today.weekday - 1)),
        today,
      ),
      _Period.month => (DateTime(today.year, today.month), today),
      _Period.custom => (_custom?.start ?? today, _custom?.end ?? today),
    };
  }

  Future<void> _select(_Period period) async {
    if (period != _Period.custom) {
      setState(() => _period = period);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _custom,
    );
    if (picked != null && mounted) {
      setState(() {
        _custom = picked;
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final (from, to) = _range();
    final fromKey = dayKey(from);
    final toKey = dayKey(to);
    Widget chip(String label, _Period p) => ChoiceChip(
      label: Text(label),
      selected: _period == p,
      onSelected: (_) => _select(p),
    );
    return Scaffold(
      appBar: KiranaBar(title: tr('reports')),
      body: ScrollColumn(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              chip(tr('today'), _Period.today),
              chip(tr('yesterday'), _Period.yesterday),
              chip(tr('this_week'), _Period.week),
              chip(tr('this_month'), _Period.month),
              chip(tr('custom_range'), _Period.custom),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fromKey == toKey
                ? formatDate(from, language)
                : '${formatDate(from, language)} – ${formatDate(to, language)}',
          ),
          Live<List<DayRollup>>(
            id: '$fromKey|$toKey',
            stream: (repo) => repo.days(from: fromKey, to: toKey),
            builder: (context, days) =>
                _ReportBody(days: days, tr: tr, language: language),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.days,
    required this.tr,
    required this.language,
  });

  final List<DayRollup> days;
  final Tr tr;
  final String language;

  @override
  Widget build(BuildContext context) {
    final s = PeriodSummary.of(days);
    final theme = Theme.of(context);
    final top = productSales(days, limit: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(tr('sales')),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BigNumber(
                  formatRupees(s.salesPaise),
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 4),
                LabelValue(tr('bills'), '${s.billCount}'),
                LabelValue(
                  tr('average_bill'),
                  formatRupees(s.averageBillPaise),
                ),
                LabelValue(
                  tr('discounts_given'),
                  formatRupees(s.discountPaise),
                ),
              ],
            ),
          ),
        ),
        SectionTitle(tr('profit')),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                LabelValue(tr('cogs'), formatRupees(s.cogsPaise)),
                LabelValue(
                  tr('gross_profit'),
                  formatRupees(s.grossProfitPaise),
                ),
                LabelValue(tr('expenses'), formatRupees(s.expensePaise)),
                const Divider(),
                LabelValue(
                  tr('net_profit'),
                  formatRupees(s.netProfitPaise),
                  strong: true,
                  color: s.netProfitPaise >= 0
                      ? KiranaColors.received
                      : KiranaColors.dues,
                ),
              ],
            ),
          ),
        ),
        SectionTitle(tr('payment_mix')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _MixRow(
                  label: tr('cash'),
                  paise: s.cashSalesPaise,
                  total: s.salesPaise,
                ),
                _MixRow(
                  label: tr('upi'),
                  paise: s.upiSalesPaise,
                  total: s.salesPaise,
                ),
                _MixRow(
                  label: tr('credit'),
                  paise: s.creditSalesPaise,
                  total: s.salesPaise,
                  color: KiranaColors.dues,
                ),
              ],
            ),
          ),
        ),
        SectionTitle(tr('money_flow')),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                LabelValue(
                  tr('collections_cash'),
                  formatRupees(s.collectionCashPaise),
                ),
                LabelValue(
                  tr('collections_upi'),
                  formatRupees(s.collectionUpiPaise),
                ),
                LabelValue(tr('purchases'), formatRupees(s.purchasePaise)),
                LabelValue(tr('net_cash'), formatRupees(s.netCashPaise)),
                LabelValue(tr('net_upi'), formatRupees(s.netUpiPaise)),
              ],
            ),
          ),
        ),
        Live<List<Product>>(
          stream: (repo) => repo.products(includeInactive: true),
          builder: (context, products) {
            final byId = {for (final p in products) p.id: p};
            final highest = top.isEmpty ? 1 : top.first.revenuePaise;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(tr('top_products')),
                if (top.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      tr('no_sales_period'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          for (final item in top)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  LabelValue(
                                    byId[item.productId]?.displayName(
                                          language,
                                        ) ??
                                        tr('unknown_product'),
                                    formatRupees(item.revenuePaise),
                                  ),
                                  Bar(
                                    fraction: highest == 0
                                        ? 0
                                        : item.revenuePaise / highest,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    tr('sold_and_profit', {
                                      'qty': formatQuantity(item.qtyMilli),
                                      'profit': formatRupees(item.profitPaise),
                                    }),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                SectionTitle(tr('inventory_value')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: BigNumber(
                      formatRupees(inventoryValue(products)),
                      style: theme.textTheme.headlineMedium,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MixRow extends StatelessWidget {
  const _MixRow({
    required this.label,
    required this.paise,
    required this.total,
    this.color,
  });

  final String label;
  final int paise;
  final int total;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : paise / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabelValue(
            label,
            '${formatRupees(paise)}  (${(fraction * 100).round()}%)',
          ),
          Bar(fraction: fraction, color: color),
        ],
      ),
    );
  }
}
