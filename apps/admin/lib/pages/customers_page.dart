import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../store_scope.dart';
import '../utils/rollups.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

/// Form fields shared by adding and editing a customer.
List<FormSpec> customerSpecs(Tr tr, {Customer? customer, List<Store> pickFrom = const []}) {
  final v = Validators(tr);
  return [
    if (pickFrom.isNotEmpty)
      ChoiceSpec('store', tr('store'), storeOptions(pickFrom),
          initial: pickFrom.length == 1 ? pickFrom.first.id : null),
    TextSpec('name', tr('name'),
        initial: customer?.name ?? '', validator: v.maxLength(80, isRequired: true)),
    TextSpec('phone', tr('phone'),
        initial: customer?.phone ?? '',
        keyboard: TextInputType.phone,
        validator: v.optionalPhone),
    TextSpec('address', tr('address'),
        initial: customer?.address ?? '', maxLines: 2, validator: v.maxLength(200)),
    TextSpec('limit', tr('credit_limit'),
        initial: customer == null || customer.creditLimitPaise == 0
            ? ''
            : formatRupees(customer.creditLimitPaise, symbol: false),
        helper: tr('credit_limit_hint'),
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        validator: v.optionalMoney),
  ];
}

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});
  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  String _query = '';
  bool _duesOnly = false;

  Future<void> _add(Tr tr, List<Store> stores) async {
    final values = await showFormDialog(
      context,
      title: tr('add_customer'),
      specs: customerSpecs(tr, pickFrom: stores),
    );
    if (values == null || !mounted) return;
    final session = context.read<SessionController>();
    runWrite(
      context,
      tr,
      () => session.repositoryFor(values.choice('store')!).saveCustomer(
            name: values.text('name'),
            phone: values.text('phone'),
            address: values.text('address'),
            creditLimitPaise: values.money('limit'),
          ),
      done: tr('saved'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final stores = scopedStores(context);
    final now = DateTime.now();
    return PageBody(
      title: tr('customers'),
      actions: [
        FilledButton.icon(
          onPressed: () => _add(tr, stores),
          icon: const Icon(Icons.person_add_alt),
          label: Text(tr('add_customer')),
        ),
      ],
      filters: [
        SearchField(
          hint: tr('search_customers'),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        FilterChip(
          label: Text(tr('with_dues_only')),
          selected: _duesOnly,
          onSelected: (v) => setState(() => _duesOnly = v),
        ),
      ],
      child: StoreStreamBuilder<List<Customer>>(
        stores: stores,
        cacheKey: 'customers',
        source: (repo) => repo.customers(),
        builder: (context, byStore) {
          final all = flatten(stores, byStore);
          final rows = all.where((row) {
            final c = row.item;
            if (_duesOnly && !c.hasDues) return false;
            if (_query.isEmpty) return true;
            return c.name.toLowerCase().contains(_query) || c.phone.contains(_query);
          }).toList();
          final outstanding = totalOutstanding(all.map((e) => e.item));
          final columns = <TableCol<StoreItem<Customer>>>[
            TableCol.text(tr('name'), (r) => r.item.name),
            TableCol.text(tr('phone'), (r) => r.item.phone),
            if (stores.length > 1) TableCol.text(tr('store'), (r) => r.store.name),
            TableCol.money(
              tr('balance'),
              (r) => r.item.balancePaise,
              color: (r) => r.item.hasDues
                  ? KiranaColors.dues
                  : (r.item.balancePaise < 0 ? KiranaColors.received : null),
            ),
            TableCol.date(tr('due_date'), (r) => r.item.dueDate),
            TableCol(
              tr('status'),
              (r) => (daysPastDue(r.item, now) ?? 0) > 0 && r.item.hasDues
                  ? StatusChip(
                      label: tr('overdue'),
                      color: KiranaColors.dues,
                      icon: Icons.schedule,
                    )
                  : const Text('-'),
            ),
            TableCol.dateTime(tr('last_transaction'), (r) => r.item.lastTxnAt),
            TableCol.dateTime(tr('last_reminder'), (r) => r.item.lastReminderAt),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(tr('customers_summary', {
                'count': '${all.length}',
                'amount': formatRupees(outstanding),
              })),
              const SizedBox(height: kGap),
              AdminTable<StoreItem<Customer>>(
                columns: columns,
                rows: rows,
                sortColumn: 0,
                emptyMessage: all.isEmpty ? tr('no_customers') : tr('no_matches'),
                onTap: (r) => context.go('/customers/${r.store.id}/${r.item.id}'),
              ),
            ],
          );
        },
      ),
    );
  }
}
