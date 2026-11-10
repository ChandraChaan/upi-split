import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../widgets/common.dart';
import 'customer_detail_screen.dart';
import 'expenses_screen.dart';
import 'market_purchase_screen.dart';
import 'reminders_screen.dart';
import 'shell.dart';
import 'stock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _midnight;
  String _today = dayKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRollover();
  }

  /// A shop phone can stay on this screen across midnight.
  void _scheduleRollover() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 2);
    _midnight?.cancel();
    _midnight = Timer(next.difference(now), () {
      _checkDay();
      _scheduleRollover();
    });
  }

  void _checkDay() {
    final key = dayKey(DateTime.now());
    if (key != _today && mounted) setState(() => _today = key);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final manager = context.canManage;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: KiranaBar(title: tr('home_title')),
      body: ScrollColumn(
        padding: const EdgeInsets.all(16),
        children: [
          Live<DayRollup>(
            id: _today,
            stream: (repo) => repo.day(_today),
            builder: (context, day) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: theme.colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('today_sales'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        BigNumber(
                          formatRupees(day.salesPaise),
                          style: theme.textTheme.displaySmall,
                        ),
                        Text(tr('bills_count', {'count': '${day.billCount}'})),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TwoColumn(
                  children: [
                    StatTile(
                      label: tr('cash'),
                      value: formatRupees(day.cashSalesPaise),
                    ),
                    StatTile(
                      label: tr('upi'),
                      value: formatRupees(day.upiSalesPaise),
                    ),
                    StatTile(
                      label: tr('credit'),
                      value: formatRupees(day.creditSalesPaise),
                      color: KiranaColors.dues,
                    ),
                    StatTile(
                      label: tr('collections'),
                      value: formatRupees(
                        day.collectionCashPaise + day.collectionUpiPaise,
                      ),
                      color: KiranaColors.received,
                    ),
                    StatTile(
                      label: tr('expenses'),
                      value: formatRupees(day.expensePaise),
                    ),
                    if (manager)
                      StatTile(
                        key: const Key('home_bought'),
                        label: tr('bought_today'),
                        value: formatRupees(day.purchasePaise),
                      ),
                  ],
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('expected_cash'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        BigNumber(
                          formatRupees(day.netCashPaise),
                          style: theme.textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (manager) _MonthCard(today: _today),
          const SizedBox(height: 10),
          Live<List<Customer>>(
            stream: (repo) => repo.customers(),
            builder: (context, customers) {
              final outstanding = totalOutstanding(customers);
              final remind = customersToRemind(customers, DateTime.now());
              final owing = customers.where((c) => c.hasDues).toList()
                ..sort((a, b) => b.balancePaise.compareTo(a.balancePaise));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TwoColumn(
                    children: [
                      StatTile(
                        label: tr('total_outstanding'),
                        value: formatRupees(outstanding),
                        color: KiranaColors.dues,
                        onTap: () => widget.onOpenTab(Tabs.khata),
                      ),
                      StatTile(
                        label: tr('customers_to_remind'),
                        value: '${remind.length}',
                        onTap: () => push(context, const RemindersScreen()),
                      ),
                    ],
                  ),
                  if (owing.isNotEmpty) ...[
                    SectionTitle(tr('top_dues')),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final c in owing.take(5))
                            ListTile(
                              key: ValueKey('top_due_${c.id}'),
                              title: Text(c.name),
                              trailing: Text(
                                formatRupees(c.balancePaise),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: KiranaColors.dues,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onTap: () => push(
                                context,
                                CustomerDetailScreen(customerId: c.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          Live<List<Product>>(
            stream: (repo) => repo.products(),
            builder: (context, products) {
              final low = products
                  .where((p) => p.isLowStock || p.stockMilli < 0)
                  .length;
              // Shops that sell from the keypad keep no product list.
              if (low == 0) return const SizedBox.shrink();
              return StatTile(
                key: const Key('home_low_stock'),
                label: tr('low_stock_items'),
                value: '$low',
                color: KiranaColors.warning,
                onTap: () => push(context, const StockScreen()),
              );
            },
          ),
          SectionTitle(tr('quick_actions')),
          TwoColumn(
            children: [
              _Action(
                key: const Key('quick_sell'),
                icon: Icons.point_of_sale,
                label: tr('sell'),
                onTap: () => widget.onOpenTab(Tabs.sell),
              ),
              _Action(
                icon: Icons.payments_outlined,
                label: tr('receive_payment'),
                onTap: () => widget.onOpenTab(Tabs.khata),
              ),
              if (manager)
                _Action(
                  key: const Key('quick_market_purchase'),
                  icon: Icons.local_shipping_outlined,
                  label: tr('market_purchase'),
                  onTap: () => push(context, const MarketPurchaseScreen()),
                ),
              _Action(
                icon: Icons.receipt_long_outlined,
                label: tr('add_expense'),
                onTap: () => push(context, const ExpensesScreen(openAdd: true)),
              ),
              _Action(
                icon: Icons.notifications_active_outlined,
                label: tr('reminders'),
                onTap: () => push(context, const RemindersScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This month's money in and out. Without product costs the shop cannot know
/// a true profit, so this says plainly what it counts.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.today});

  final String today;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final from = '${today.substring(0, 8)}01';
    return Live<List<DayRollup>>(
      id: today,
      stream: (repo) => repo.days(from: from, to: today),
      builder: (context, days) {
        int sum(int Function(DayRollup d) f) =>
            days.fold(0, (total, d) => total + f(d));
        final sold = sum((d) => d.salesPaise);
        final bought = sum((d) => d.purchasePaise);
        final spent = sum((d) => d.expensePaise);
        final left = sold - bought - spent;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('month_title'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                LabelValue(tr('month_sold'), formatRupees(sold)),
                LabelValue(tr('month_bought'), formatRupees(bought)),
                LabelValue(tr('expenses'), formatRupees(spent)),
                const Divider(),
                LabelValue(
                  tr('month_left'),
                  formatRupees(left),
                  key: const Key('home_profit'),
                  color: left < 0 ? KiranaColors.dues : KiranaColors.received,
                  strong: true,
                ),
                Text(
                  tr('month_left_hint'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 64)),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
