import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import 'billing_screen.dart';
import 'home_screen.dart';
import 'khata_screen.dart';
import 'more_screen.dart';
import 'stock_screen.dart';

/// The five bottom-navigation tabs. Tabs are built on first visit and then
/// kept alive, so a half-made bill survives switching to Khata and back.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final Set<int> _visited = {0};

  void _open(int index) => setState(() {
    _index = index;
    _visited.add(index);
  });

  Widget _tab(int index) => switch (index) {
    0 => HomeScreen(onOpenTab: _open),
    1 => const BillingScreen(),
    2 => const KhataScreen(),
    3 => const StockScreen(),
    _ => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < 5; i++)
            _visited.contains(i) ? _tab(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _open,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: tr('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale),
            label: tr('billing'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            label: tr('khata'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.inventory_2_outlined),
            label: tr('stock'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz),
            label: tr('more'),
          ),
        ],
      ),
    );
  }
}
