import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

class StoresPage extends StatelessWidget {
  const StoresPage({super.key});

  List<FormSpec> _specs(Tr tr, Store? store) {
    final v = Validators(tr);
    return [
      TextSpec('name', tr('store_name'),
          initial: store?.name ?? '', validator: v.maxLength(80, isRequired: true)),
      TextSpec('address', tr('address'),
          initial: store?.address ?? '', maxLines: 2, validator: v.maxLength(200)),
      TextSpec('phone', tr('phone'),
          initial: store?.phone ?? '', keyboard: TextInputType.phone, validator: v.optionalPhone),
      TextSpec('gstin', tr('gstin'), initial: store?.gstin ?? '', validator: v.optionalGstin),
      TextSpec('upi', tr('upi_id'), initial: store?.upiId ?? '', validator: v.optionalUpi),
      TextSpec('footer', tr('receipt_footer'),
          initial: store?.receiptFooter ?? '', maxLines: 2, validator: v.maxLength(200)),
    ];
  }

  Future<void> _edit(BuildContext context, Tr tr, SessionController session, Store? store) async {
    final values = await showFormDialog(
      context,
      title: store == null ? tr('add_store') : tr('edit_store'),
      specs: _specs(tr, store),
    );
    if (values == null || !context.mounted) return;
    final next = Store(
      id: store?.id ?? '',
      name: values.text('name'),
      address: values.text('address'),
      phone: values.text('phone'),
      gstin: values.text('gstin').toUpperCase(),
      upiId: values.text('upi'),
      receiptFooter: values.text('footer'),
    );
    final businessId = session.business!.id;
    final sync = context.read<SyncMonitor>();
    if (store == null) {
      sync.track('addStore', () => session.businesses.addStore(businessId, next));
    } else {
      sync.track('updateStore', () => session.businesses.updateStore(businessId, next));
    }
    showMessage(context, tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    if (!(session.member?.role.isOwner ?? false)) {
      return PageBody(title: tr('stores'), child: EmptyState(message: tr('owner_only')));
    }
    final columns = <TableCol<Store>>[
      TableCol.text(tr('store_name'), (s) => s.name),
      TableCol.text(tr('address'), (s) => s.address),
      TableCol.text(tr('phone'), (s) => s.phone),
      TableCol.text(tr('gstin'), (s) => s.gstin),
      TableCol.text(tr('upi_id'), (s) => s.upiId),
      TableCol.text(tr('receipt_footer'), (s) => s.receiptFooter, sortable: false),
    ];
    return PageBody(
      title: tr('stores'),
      actions: [
        FilledButton.icon(
          onPressed: () => _edit(context, tr, session, null),
          icon: const Icon(Icons.add_business_outlined),
          label: Text(tr('add_store')),
        ),
      ],
      child: AdminTable<Store>(
        columns: columns,
        rows: session.allStores,
        sortColumn: 0,
        emptyMessage: tr('no_stores_owner'),
        onTap: (s) => _edit(context, tr, session, s),
      ),
    );
  }
}
