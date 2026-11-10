import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import 'home_screen.dart';
import 'khata_screen.dart';
import 'more_screen.dart';
import 'sell_screen.dart';

/// Tab indexes, for screens that send the user to another tab.
abstract final class Tabs {
  static const sell = 0;
  static const khata = 1;
  static const today = 2;
  static const more = 3;
}

/// The bottom-navigation tabs. Selling comes first because it happens all
/// day. Tabs are built on first visit and then kept alive, so a half-typed
/// sale survives a look at the khata.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = Tabs.sell;
  final Set<int> _visited = {Tabs.sell};

  void _open(int index) => setState(() {
    _index = index;
    _visited.add(index);
  });

  Widget _tab(int index) => switch (index) {
    Tabs.sell => const SellScreen(),
    Tabs.khata => const KhataScreen(),
    Tabs.today => HomeScreen(onOpenTab: _open),
    _ => const MoreScreen(),
  };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < 4; i++)
            _visited.contains(i) ? _tab(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _open,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.point_of_sale),
            label: tr('sell'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            label: tr('khata'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            label: tr('today'),
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
