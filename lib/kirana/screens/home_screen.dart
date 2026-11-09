import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../widgets/common.dart';
import 'expenses_screen.dart';
import 'reminders_screen.dart';

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
                        key: const Key('home_profit'),
                        label: tr('profit'),
                        value: formatRupees(day.netProfitPaise),
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
          const SizedBox(height: 10),
          Live<List<Customer>>(
            stream: (repo) => repo.customers(),
            builder: (context, customers) {
              final outstanding = totalOutstanding(customers);
              final remind = customersToRemind(customers, DateTime.now());
              return TwoColumn(
                children: [
                  StatTile(
                    label: tr('total_outstanding'),
                    value: formatRupees(outstanding),
                    color: KiranaColors.dues,
                    onTap: () => widget.onOpenTab(2),
                  ),
                  StatTile(
                    label: tr('customers_to_remind'),
                    value: '${remind.length}',
                    onTap: () => push(context, const RemindersScreen()),
                  ),
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
              return StatTile(
                label: tr('low_stock_items'),
                value: '$low',
                color: low > 0 ? KiranaColors.warning : null,
                onTap: () => widget.onOpenTab(3),
              );
            },
          ),
          SectionTitle(tr('quick_actions')),
          TwoColumn(
            children: [
              _Action(
                key: const Key('quick_new_bill'),
                icon: Icons.point_of_sale,
                label: tr('new_bill'),
                onTap: () => widget.onOpenTab(1),
              ),
              _Action(
                icon: Icons.payments_outlined,
                label: tr('receive_payment'),
                onTap: () => widget.onOpenTab(2),
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
