import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../widgets/common.dart';

const double _wideBreakpoint = 960;
const double _sidebarWidth = 248;

class _NavItem {
  const _NavItem(this.path, this.icon, this.label, {this.ownerOnly = false, this.usesStores = true});
  final String path;
  final IconData icon;
  final String Function(Tr tr) label;
  final bool ownerOnly;
  final bool usesStores;
}

final List<_NavItem> _navItems = [
  _NavItem('/dashboard', Icons.dashboard_outlined, (tr) => tr('dashboard')),
  _NavItem('/customers', Icons.people_outline, (tr) => tr('customers')),
  _NavItem('/products', Icons.inventory_2_outlined, (tr) => tr('products')),
  _NavItem('/bills', Icons.receipt_long_outlined, (tr) => tr('bills')),
  _NavItem('/suppliers', Icons.local_shipping_outlined, (tr) => tr('suppliers')),
  _NavItem('/expenses', Icons.payments_outlined, (tr) => tr('expenses')),
  _NavItem('/reports', Icons.bar_chart_outlined, (tr) => tr('reports')),
  _NavItem('/staff', Icons.badge_outlined, (tr) => tr('staff'), usesStores: false),
  _NavItem('/stores', Icons.storefront_outlined, (tr) => tr('stores'),
      ownerOnly: true, usesStores: false),
  _NavItem('/settings', Icons.settings_outlined, (tr) => tr('settings'), usesStores: false),
];

_NavItem _itemFor(String path) => _navItems.firstWhere(
      (i) => path == i.path || path.startsWith('${i.path}/'),
      orElse: () => _navItems.first,
    );

/// Sidebar and top bar around every signed-in page.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    if (session.stage != SessionStage.ready || session.member == null) {
      return const Scaffold();
    }
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final current = _itemFor(path);
    final showSelector = current.usesStores;
    final nav = _NavList(current: current);
    return Scaffold(
      drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
      appBar: AppBar(
        title: Text(session.business?.name ?? tr('app_name'), overflow: TextOverflow.ellipsis),
        actions: [
          if (wide && showSelector)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(width: 240, child: StoreSelector()),
            ),
          SyncIndicator(showLabel: wide),
          const LanguageSwitch(),
          const SizedBox(width: 8),
        ],
        bottom: !wide && showSelector
            ? const PreferredSize(
                preferredSize: Size.fromHeight(56),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: StoreSelector(),
                ),
              )
            : null,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) SizedBox(width: _sidebarWidth, child: Material(child: nav)),
          if (wide) const VerticalDivider(width: 1),
          Expanded(
            child: session.stores.isEmpty && current.usesStores
                ? _NoStores(isOwner: session.member!.role.isOwner)
                : child,
          ),
        ],
      ),
    );
  }
}

class _NoStores extends StatelessWidget {
  const _NoStores({required this.isOwner});
  final bool isOwner;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return EmptyState(
      icon: Icons.storefront_outlined,
      message: isOwner ? tr('no_stores_owner') : tr('no_stores_manager'),
      action: isOwner
          ? FilledButton(onPressed: () => context.go('/stores'), child: Text(tr('add_store')))
          : null,
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.current});
  final _NavItem current;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final isOwner = session.member?.role.isOwner ?? false;
    final scheme = Theme.of(context).colorScheme;
    final drawer = Scaffold.maybeOf(context)?.isDrawerOpen ?? false;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Text(tr('app_name'), style: Theme.of(context).textTheme.titleLarge),
        ),
        for (final item in _navItems)
          if (!item.ownerOnly || isOwner)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                dense: true,
                selected: identical(item, current),
                selectedTileColor: scheme.secondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: Icon(item.icon),
                title: Text(item.label(tr)),
                onTap: () {
                  if (drawer) Navigator.of(context).pop();
                  context.go(item.path);
                },
              ),
            ),
      ],
    );
  }
}

/// All stores or one store. With a single store there is nothing to choose.
class StoreSelector extends StatelessWidget {
  const StoreSelector({super.key});
  static const _all = '__all__';

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final scope = context.watch<StoreScope>();
    final stores = session.stores;
    if (stores.isEmpty) return const SizedBox.shrink();
    if (stores.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(stores.first.name, overflow: TextOverflow.ellipsis),
      );
    }
    final inView = scope.resolve(stores);
    final value = inView.length == 1 ? inView.first.id : _all;
    return DropdownButtonFormField<String>(
      key: ValueKey('store-selector-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(Icons.storefront_outlined, size: 20),
        hintText: tr('store'),
      ),
      items: [
        DropdownMenuItem(value: _all, child: Text(tr('all_stores'))),
        for (final s in stores)
          DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) => scope.select(v == _all ? null : v),
    );
  }
}

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.showLabel});
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final sync = context.watch<SyncMonitor>();
    final (icon, label, color) = switch (sync.state) {
      SyncState.synced => (Icons.cloud_done_outlined, tr('sync_synced'), KiranaColors.received),
      SyncState.syncing => (Icons.cloud_upload_outlined, tr('sync_syncing'), KiranaColors.warning),
      SyncState.offline => (Icons.cloud_off_outlined, tr('sync_offline'), KiranaColors.dues),
    };
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Flips between the two languages.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({super.key});
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final te = session.language == 'te';
    return TextButton.icon(
      onPressed: () => session.setLanguage(te ? 'en' : 'te'),
      icon: const Icon(Icons.translate, size: 18),
      label: Text(te ? tr('english') : tr('telugu')),
    );
  }
}
