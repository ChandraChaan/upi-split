import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

List<FormSpec> supplierSpecs(Tr tr, {Supplier? supplier, List<Store> pickFrom = const []}) {
  final v = Validators(tr);
  return [
    if (pickFrom.isNotEmpty)
      ChoiceSpec('store', tr('store'), storeOptions(pickFrom),
          initial: pickFrom.length == 1 ? pickFrom.first.id : null),
    TextSpec('name', tr('name'),
        initial: supplier?.name ?? '', validator: v.maxLength(80, isRequired: true)),
    TextSpec('phone', tr('phone'),
        initial: supplier?.phone ?? '', keyboard: TextInputType.phone, validator: v.optionalPhone),
    TextSpec('address', tr('address'),
        initial: supplier?.address ?? '', maxLines: 2, validator: v.maxLength(200)),
    TextSpec('gstin', tr('gstin'), initial: supplier?.gstin ?? '', validator: v.optionalGstin),
  ];
}

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});
  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  String _query = '';

  Future<void> _add(Tr tr, List<Store> stores) async {
    final values = await showFormDialog(
      context,
      title: tr('add_supplier'),
      specs: supplierSpecs(tr, pickFrom: stores),
    );
    if (values == null || !mounted) return;
    final repo = context.read<SessionController>().repositoryFor(values.choice('store')!);
    runWrite(
      context,
      tr,
      () => repo.saveSupplier(
        name: values.text('name'),
        phone: values.text('phone'),
        address: values.text('address'),
        gstin: values.text('gstin').toUpperCase(),
      ),
      done: tr('saved'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    return PageBody(
      title: tr('suppliers'),
      actions: [
        FilledButton.icon(
          onPressed: () => _add(tr, stores),
          icon: const Icon(Icons.add_business_outlined),
          label: Text(tr('add_supplier')),
        ),
      ],
      filters: [
        SearchField(
          hint: tr('search_suppliers'),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      ],
      child: StoreStreamBuilder<List<Supplier>>(
        stores: stores,
        cacheKey: 'suppliers',
        source: (repo) => repo.suppliers(),
        builder: (context, byStore) {
          final all = flatten(stores, byStore);
          final rows = all
              .where((r) =>
                  _query.isEmpty ||
                  r.item.name.toLowerCase().contains(_query) ||
                  r.item.phone.contains(_query))
              .toList();
          final columns = <TableCol<StoreItem<Supplier>>>[
            TableCol.text(tr('name'), (r) => r.item.name),
            TableCol.text(tr('phone'), (r) => r.item.phone),
            if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
            TableCol.text(tr('gstin'), (r) => r.item.gstin),
            TableCol.money(tr('payable'), (r) => r.item.balancePaise),
          ];
          return AdminTable<StoreItem<Supplier>>(
            columns: columns,
            rows: rows,
            sortColumn: 0,
            emptyMessage: all.isEmpty ? tr('no_suppliers') : tr('no_matches'),
            onTap: (r) => context.go('/suppliers/${r.store.id}/${r.item.id}'),
          );
        },
      ),
    );
  }
}
