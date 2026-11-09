import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/dates.dart';
import '../utils/platform.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';
import 'customers_page.dart';

class CustomerDetailPage extends StatelessWidget {
  const CustomerDetailPage({super.key, required this.storeId, required this.customerId});
  final String storeId;
  final String customerId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final store = accessibleStore(context, storeId);
    void back() => context.go('/customers');
    if (store == null) {
      return PageBody(title: tr('customer'), onBack: back, child: NotFoundBody(onBack: back));
    }
    final session = context.read<SessionController>();
    return StoreStreamBuilder<Customer?>(
      stores: [store],
      cacheKey: 'customer-$customerId',
      source: (repo) => repo.customer(customerId),
      builder: (context, data) {
        final customer = data[store.id];
        if (customer == null) {
          return PageBody(title: tr('customer'), onBack: back, child: NotFoundBody(onBack: back));
        }
        return PageBody(
          title: customer.name,
          onBack: back,
          child: StoreStreamBuilder<List<KhataEntry>>(
            stores: [store],
            cacheKey: 'khata-$customerId',
            source: (repo) => repo.khata(customerId, limit: 5000),
            builder: (context, khata) => _CustomerBody(
              store: store,
              customer: customer,
              entries: khata[store.id] ?? const [],
              repo: session.repositoryFor(store.id),
            ),
          ),
        );
      },
    );
  }
}

/// A statement line with the balance as it stood after that entry.
class _StatementRow {
  const _StatementRow(this.entry, this.balanceAfter);
  final KhataEntry entry;
  final int balanceAfter;
}

/// Entries come newest first, so balances are worked back from the current one.
List<_StatementRow> _statementRows(List<KhataEntry> entries, int currentBalance) {
  var balance = currentBalance;
  final rows = <_StatementRow>[];
  for (final entry in entries) {
    rows.add(_StatementRow(entry, balance));
    balance -= entry.amountPaise;
  }
  return rows;
}

String _kindLabel(Tr tr, KhataEntry e) {
  if (e.reversesId != null) return tr('khata_reversal');
  return switch (e.kind) {
    KhataKind.purchase => tr('khata_purchase'),
    KhataKind.payment => tr('khata_payment'),
    KhataKind.adjustment => tr('khata_adjustment'),
  };
}

class _CustomerBody extends StatelessWidget {
  const _CustomerBody({
    required this.store,
    required this.customer,
    required this.entries,
    required this.repo,
  });
  final Store store;
  final Customer customer;
  final List<KhataEntry> entries;
  final StoreRepository repo;

  Future<void> _payment(BuildContext context, Tr tr) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('record_payment'),
      specs: [
        TextSpec('amount', tr('amount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.positiveMoney,
            formatters: [moneyInputFormatter]),
        ChoiceSpec('method', tr('payment_method'), {'cash': tr('cash'), 'upi': tr('upi')},
            initial: 'cash'),
        TextSpec('note', tr('note'), validator: v.maxLength(200)),
        if (customer.dueDate != null)
          SwitchSpec('clearDue', tr('clear_due_date'), initial: true),
      ],
      liveNotice: (values) {
        final paise = parseRupees(values.text('amount'));
        return paise != null && paise > customer.balancePaise ? tr('payment_over_dues') : null;
      },
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.recordPayment(
        customerId: customer.id,
        amountPaise: values.money('amount'),
        method: values.choice('method') == 'upi' ? PaymentMethod.upi : PaymentMethod.cash,
        note: values.text('note'),
        clearDueDate: values.flag('clearDue'),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _purchase(BuildContext context, Tr tr) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('credit_purchase'),
      specs: [
        TextSpec('amount', tr('amount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.positiveMoney,
            formatters: [moneyInputFormatter]),
        TextSpec('note', tr('note'), validator: v.maxLength(200)),
      ],
      liveNotice: (values) {
        final paise = parseRupees(values.text('amount')) ?? 0;
        return customer.creditLimitPaise > 0 &&
                customer.balancePaise + paise > customer.creditLimitPaise
            ? tr('over_credit_limit')
            : null;
      },
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.recordKhataPurchase(
        customerId: customer.id,
        amountPaise: values.money('amount'),
        note: values.text('note'),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _adjustment(BuildContext context, Tr tr) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('adjustment'),
      description: tr('adjustment_hint'),
      specs: [
        ChoiceSpec(
          'direction',
          tr('adjustment_direction'),
          {'add': tr('adjust_add'), 'reduce': tr('adjust_reduce')},
          initial: 'reduce',
        ),
        TextSpec('amount', tr('amount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            validator: v.positiveMoney,
            formatters: [moneyInputFormatter]),
        TextSpec('note', tr('reason'), validator: v.maxLength(200, isRequired: true)),
      ],
    );
    if (values == null || !context.mounted) return;
    final signed = values.money('amount') * (values.choice('direction') == 'add' ? 1 : -1);
    runWrite(
      context,
      tr,
      () => repo.recordAdjustment(
        customerId: customer.id,
        signedPaise: signed,
        note: values.text('note'),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _reverse(BuildContext context, Tr tr, KhataEntry entry) async {
    final v = Validators(tr);
    final values = await showFormDialog(
      context,
      title: tr('reverse_entry'),
      description: tr('reverse_entry_hint', {
        'kind': _kindLabel(tr, entry),
        'amount': formatRupees(entry.amountPaise.abs()),
      }),
      submitLabel: tr('reverse'),
      specs: [TextSpec('note', tr('reason'), validator: v.maxLength(200, isRequired: true))],
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.reverseKhataEntry(entry, note: values.text('note')),
      done: tr('saved'),
    );
  }

  Future<void> _dueDate(BuildContext context, Tr tr) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: customer.dueDate ?? DateTime(now.year, now.month, now.day + 7),
    );
    if (picked == null || !context.mounted) return;
    // The end of the day, so it does not count as overdue on the day itself.
    final due = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
    runWrite(context, tr, () => repo.setDueDate(customer.id, due), done: tr('saved'));
  }

  Future<void> _edit(BuildContext context, Tr tr) async {
    final values = await showFormDialog(
      context,
      title: tr('edit_customer'),
      specs: customerSpecs(tr, customer: customer),
    );
    if (values == null || !context.mounted) return;
    runWrite(
      context,
      tr,
      () => repo.saveCustomer(
        id: customer.id,
        name: values.text('name'),
        phone: values.text('phone'),
        address: values.text('address'),
        creditLimitPaise: values.money('limit'),
      ),
      done: tr('saved'),
    );
  }

  Future<void> _archive(BuildContext context, Tr tr) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('archive_customer'),
      message: customer.balancePaise != 0
          ? tr('archive_customer_balance', {'amount': formatRupees(customer.balancePaise)})
          : tr('archive_customer_body'),
      confirmLabel: tr('archive'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    runWrite(context, tr, () => repo.archiveCustomer(customer.id));
    context.go('/customers');
  }

  Future<void> _remind(BuildContext context, Tr tr, String language) async {
    final uri = whatsappUri(
      customer.phone,
      reminderMessage(
        language: language,
        shopName: store.name,
        customer: customer,
        upiId: store.upiId,
      ),
    );
    if (uri == null) {
      showMessage(context, tr('no_valid_phone'));
      return;
    }
    final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!context.mounted) return;
    if (!opened) {
      showMessage(context, tr('could_not_open_whatsapp'));
      return;
    }
    runWrite(context, tr, () => repo.logReminder(customer: customer, channel: 'whatsapp'));
  }

  void _exportCsv(Tr tr, List<TableCol<_StatementRow>> columns, List<_StatementRow> rows) {
    final safeName = customer.name.replaceAll(RegExp(r'[^\w]+'), '_');
    downloadTextFile(
      'statement_$safeName.csv',
      buildCsv([
        [tr('customer'), customer.name],
        [tr('phone'), customer.phone],
        [tr('balance'), csvMoney(customer.balancePaise)],
        const [],
        ...tableCsvRows(columns, rows),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.select<SessionController, String>((s) => s.language);
    final now = DateTime.now();
    final reversed = {for (final e in entries) if (e.reversesId != null) e.reversesId!};
    final rows = _statementRows(entries, customer.balancePaise);
    bool canReverse(KhataEntry e) =>
        e.reversesId == null && e.billId == null && !reversed.contains(e.id);

    final columns = <TableCol<_StatementRow>>[
      TableCol.dateTime(tr('date'), (r) => r.entry.at),
      TableCol.text(tr('type'), (r) => _kindLabel(tr, r.entry)),
      TableCol.text(tr('method'), (r) => methodLabel(tr, r.entry.method), sortable: false),
      TableCol.text(tr('note'), (r) => r.entry.note, sortable: false),
      TableCol.text(tr('by'), (r) => r.entry.byName),
      TableCol.money(tr('added_to_dues'), (r) => r.entry.amountPaise > 0 ? r.entry.amountPaise : 0),
      TableCol.money(
          tr('paid_or_reduced'), (r) => r.entry.amountPaise < 0 ? -r.entry.amountPaise : 0),
      TableCol.money(tr('balance'), (r) => r.balanceAfter),
      if (!customer.archived)
        TableCol(
          '',
          (r) => canReverse(r.entry)
              ? TextButton(
                  onPressed: () => _reverse(context, tr, r.entry),
                  child: Text(tr('reverse')),
                )
              : const SizedBox.shrink(),
        ),
    ];

    final actions = <Widget>[
      FilledButton.icon(
        onPressed: () => _payment(context, tr),
        icon: const Icon(Icons.call_received),
        label: Text(tr('record_payment')),
      ),
      OutlinedButton.icon(
        onPressed: () => _purchase(context, tr),
        icon: const Icon(Icons.shopping_basket_outlined),
        label: Text(tr('credit_purchase')),
      ),
      OutlinedButton.icon(
        onPressed: () => _adjustment(context, tr),
        icon: const Icon(Icons.tune),
        label: Text(tr('adjustment')),
      ),
      OutlinedButton.icon(
        onPressed: () => _dueDate(context, tr),
        icon: const Icon(Icons.event_outlined),
        label: Text(tr('set_due_date')),
      ),
      if (customer.dueDate != null)
        OutlinedButton.icon(
          onPressed: () =>
              runWrite(context, tr, () => repo.setDueDate(customer.id, null), done: tr('saved')),
          icon: const Icon(Icons.event_busy_outlined),
          label: Text(tr('clear_due_date')),
        ),
      if (customer.hasDues)
        OutlinedButton.icon(
          onPressed: () => _remind(context, tr, language),
          icon: const Icon(Icons.chat_outlined),
          label: Text(tr('whatsapp_reminder')),
        ),
      OutlinedButton.icon(
        onPressed: () => _edit(context, tr),
        icon: const Icon(Icons.edit_outlined),
        label: Text(tr('edit')),
      ),
      OutlinedButton.icon(
        onPressed: () => _archive(context, tr),
        icon: const Icon(Icons.archive_outlined),
        label: Text(tr('archive')),
      ),
    ];

    final isOverdue = customer.hasDues && customer.isOverdue(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: TileGrid(
            children: [
              StatTile(
                label: customer.balancePaise < 0 ? tr('advance_held') : tr('outstanding'),
                value: formatRupees(customer.balancePaise.abs()),
              ),
              StatTile(
                label: tr('due_date'),
                value: customer.dueDate == null ? '-' : formatDate(customer.dueDate!),
                icon: isOverdue ? Icons.schedule : null,
                color: KiranaColors.dues,
              ),
              StatTile(
                label: tr('credit_limit'),
                value: customer.creditLimitPaise == 0
                    ? tr('no_limit')
                    : formatRupees(customer.creditLimitPaise),
              ),
              StatTile(
                label: tr('last_reminder'),
                value: customer.lastReminderAt == null ? '-' : formatDate(customer.lastReminderAt!),
              ),
            ],
          ),
        ),
        const SizedBox(height: kGap),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Muted('${tr('store')}: ${store.name}'),
            if (customer.phone.isNotEmpty) Muted('${tr('phone')}: ${customer.phone}'),
            if (customer.address.isNotEmpty) Muted('${tr('address')}: ${customer.address}'),
          ],
        ),
        const SizedBox(height: kGap),
        if (customer.archived)
          Muted(tr('customer_archived_note'))
        else
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text(tr('statement'), style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: rows.isEmpty ? null : () => _exportCsv(tr, columns, rows),
              icon: const Icon(Icons.download_outlined),
              label: Text(tr('export_csv')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AdminTable<_StatementRow>(
          columns: columns,
          rows: rows,
          sortColumn: 0,
          ascending: false,
          emptyMessage: tr('no_khata_entries'),
        ),
      ],
    );
  }
}
