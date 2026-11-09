import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'shop_stub.dart' if (dart.library.io) 'kirana/kirana_root.dart';

typedef ShopBuilder =
    Widget Function(SharedPreferences prefs, VoidCallback onExit);

/// Shows bill splitting or the shop, one at a time.
///
/// They are swapped here instead of pushing the shop as a route because each
/// has its own MaterialApp, and nested ones would fight over the back button.
class AppSwitcher extends StatefulWidget {
  const AppSwitcher({
    super.key,
    required this.prefs,
    this.enabled = shopAvailable,
    this.shopBuilder = buildShop,
  });

  final SharedPreferences prefs;
  final bool enabled;
  final ShopBuilder shopBuilder;

  @override
  State<AppSwitcher> createState() => _AppSwitcherState();
}

class _AppSwitcherState extends State<AppSwitcher> {
  /// A shopkeeper should land back in the shop; everyone else in UPI Split.
  static const _openInShopKey = 'open_in_shop';

  late bool _inShop =
      widget.enabled && (widget.prefs.getBool(_openInShopKey) ?? false);

  void _show({required bool shop}) {
    widget.prefs.setBool(_openInShopKey, shop).ignore();
    setState(() => _inShop = shop);
  }

  @override
  Widget build(BuildContext context) {
    if (_inShop) {
      return widget.shopBuilder(widget.prefs, () => _show(shop: false));
    }
    return UpiSplitApp(
      onOpenShop: widget.enabled ? () => _show(shop: true) : null,
    );
  }
}
