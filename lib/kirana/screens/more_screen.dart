import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../shop_exit.dart';
import '../widgets/common.dart';
import 'bills_screen.dart';
import 'expenses_screen.dart';
import 'market_purchase_screen.dart';
import 'reminders_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';
import 'suppliers_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final manager = context.canManage;
    final exit = context.read<ShopExit?>();
    Widget item(IconData icon, String label, Widget screen, {Key? key}) =>
        ListTile(
          key: key,
          minTileHeight: 60,
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, screen),
        );
    return Scaffold(
      appBar: KiranaBar(title: tr('more')),
      body: ListView(
        children: [
          if (manager)
            item(
              Icons.local_shipping_outlined,
              tr('purchases'),
              const PurchasesScreen(),
              key: const Key('more_purchases'),
            ),
          item(
            Icons.inventory_2_outlined,
            tr('products_stock'),
            const StockScreen(),
            key: const Key('more_stock'),
          ),
          item(
            Icons.notifications_active_outlined,
            tr('reminders'),
            const RemindersScreen(),
            key: const Key('more_reminders'),
          ),
          item(
            Icons.receipt_outlined,
            tr('bills'),
            const BillsScreen(),
            key: const Key('more_bills'),
          ),
          item(
            Icons.account_balance_wallet_outlined,
            tr('expenses'),
            const ExpensesScreen(),
            key: const Key('more_expenses'),
          ),
          if (manager) ...[
            item(
              Icons.local_shipping_outlined,
              tr('suppliers'),
              const SuppliersScreen(),
              key: const Key('more_suppliers'),
            ),
            item(
              Icons.bar_chart,
              tr('reports'),
              const ReportsScreen(),
              key: const Key('more_reports'),
            ),
          ],
          item(
            Icons.settings_outlined,
            tr('settings'),
            const SettingsScreen(),
            key: const Key('more_settings'),
          ),
          if (exit != null)
            ListTile(
              key: const Key('more_upi_split'),
              minTileHeight: 60,
              leading: const Icon(Icons.call_split),
              title: const Text('UPI Split'),
              onTap: exit.leave,
            ),
        ],
      ),
    );
  }
}
