import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'customer_form_screen.dart';
import 'khata_screen.dart';
import 'reminders_screen.dart';

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Live<Customer?>(
      id: customerId,
      stream: (repo) => repo.customer(customerId),
      loading: const Scaffold(body: LoadingState()),
      builder: (context, customer) {
        if (customer == null) {
          return Scaffold(
            appBar: KiranaBar(title: tr('customer')),
            body: EmptyState(
              icon: Icons.person_off_outlined,
              message: tr('no_data'),
            ),
          );
        }
        return _Detail(customer: customer);
      },
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.customer});

  final Customer customer;

  Future<void> _pickDueDate(BuildContext context) async {
    final tr = context.trNow;
    final repo = context.session.repository;
    final now = DateTime.now();
    final current = customer.dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && current.isAfter(now) ? current : now,
      firstDate: startOfDay(now),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !context.mounted) return;
    repo.setDueDate(customer.id, endOfDay(picked));
    showMessage(context, tr('saved'));
  }

  void _clearDueDate(BuildContext context) {
    final tr = context.trNow;
    context.session.repository.setDueDate(customer.id, null);
    showMessage(context, tr('saved'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    final theme = Theme.of(context);
    final balance = customer.balancePaise;
    final now = DateTime.now();
    final due = customer.dueDate;
    return Scaffold(
      appBar: KiranaBar(
        title: customer.name,
        actions: [
          IconButton(
            key: const Key('customer_edit'),
            tooltip: tr('edit'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                push(context, CustomerFormScreen(customer: customer)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    balance < 0 ? tr('advance') : tr('dues_label'),
                    style: theme.textTheme.titleMedium,
                  ),
                  BigNumber(
                    key: const Key('customer_balance'),
                    formatRupees(balance.abs()),
                    color: balanceColor(context, balance),
                    style: theme.textTheme.displaySmall,
                  ),
                  if (customer.phone.isNotEmpty) Text(customer.phone),
                  if (customer.address.isNotEmpty) Text(customer.address),
                  if (manager && customer.creditLimitPaise > 0)
                    Text(
                      tr('credit_limit_value', {
                        'amount': formatRupees(customer.creditLimitPaise),
                      }),
                    ),
                  if (customer.lastReminderAt != null)
                    Text(
                      tr('last_reminded', {
                        'date': formatDate(customer.lastReminderAt!, language),
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TwoColumn(
            children: [
              FilledButton(
                key: const Key('record_payment'),
                style: FilledButton.styleFrom(
                  backgroundColor: KiranaColors.received,
                  minimumSize: const Size(0, 56),
                ),
                onPressed: () => showSheet<void>(
                  context,
                  (_) => _PaymentSheet(customer: customer),
                ),
                child: Text(tr('receive_payment'), textAlign: TextAlign.center),
              ),
              FilledButton(
                key: const Key('record_credit'),
                style: FilledButton.styleFrom(
                  backgroundColor: KiranaColors.dues,
                  minimumSize: const Size(0, 56),
                ),
                onPressed: () => showSheet<void>(
                  context,
                  (_) => _CreditSheet(customer: customer),
                ),
                child: Text(tr('record_credit'), textAlign: TextAlign.center),
              ),
            ],
          ),
          Card(
            child: ListTile(
              key: const Key('due_date_tile'),
              minTileHeight: 60,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                due == null
                    ? tr('set_due_date')
                    : tr('due_on', {'date': formatDate(due, language)}),
              ),
              subtitle: customer.isOverdue(now)
                  ? Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Flag(tr('overdue'), color: KiranaColors.dues),
                    )
                  : null,
              trailing: due == null
                  ? null
                  : IconButton(
                      tooltip: tr('clear_due_date'),
                      icon: const Icon(Icons.close),
                      onPressed: () => _clearDueDate(context),
                    ),
              onTap: () => _pickDueDate(context),
            ),
          ),
          if (customer.hasDues) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('remind_whatsapp'),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(tr('whatsapp')),
                    onPressed: () => sendReminder(
                      context,
                      customer,
                      ReminderChannel.whatsapp,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('remind_sms'),
                    icon: const Icon(Icons.sms_outlined),
                    label: Text(tr('sms')),
                    onPressed: () =>
                        sendReminder(context, customer, ReminderChannel.sms),
                  ),
                ),
              ],
            ),
          ],
          if (manager) ...[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('khata_adjust'),
                icon: const Icon(Icons.tune),
                label: Text(tr('adjustment')),
                onPressed: () => showSheet<void>(
                  context,
                  (_) => _AdjustmentSheet(customer: customer),
                ),
              ),
            ),
          ],
          SectionTitle(tr('ledger')),
          Live<List<KhataEntry>>(
            id: customer.id,
            stream: (repo) => repo.khata(customer.id),
            builder: (context, entries) {
              if (entries.isEmpty) {
                return EmptyState(
                  icon: Icons.history,
                  message: tr('no_entries'),
                );
              }
              final ids = entries.map((e) => e.id).toSet();
              final rows = <Widget>[];
              // Newest first, so walk back from the current balance.
              var running = balance;
              for (final entry in entries) {
                rows.add(
                  _EntryRow(
                    entry: entry,
                    balanceAfter: running,
                    tr: tr,
                    language: language,
                    canReverse:
                        manager &&
                        entry.billId == null &&
                        entry.reversesId == null &&
                        !ids.contains('rev_${entry.id}'),
                  ),
                );
                running -= entry.amountPaise;
              }
              return Column(children: rows);
            },
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.balanceAfter,
    required this.tr,
    required this.language,
    required this.canReverse,
  });

  final KhataEntry entry;
  final int balanceAfter;
  final Tr tr;
  final String language;
  final bool canReverse;

  Future<void> _reverse(BuildContext context) async {
    final repo = context.session.repository;
    final ok = await confirm(
      context,
      title: tr('reverse_title'),
      body: tr('reverse_body', {
        'amount': formatRupees(entry.amountPaise.abs()),
      }),
      action: tr('reverse_entry'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      repo.reverseKhataEntry(entry);
      showMessage(context, tr('saved'));
    } on InvalidOperation {
      showMessage(context, tr('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addsDues = entry.amountPaise > 0;
    final color = addsDues ? KiranaColors.dues : KiranaColors.received;
    final details = [
      if (entry.method != null && entry.method != PaymentMethod.credit)
        methodLabel(tr, entry.method!),
      if (entry.note.isNotEmpty) entry.note,
    ].join(' · ');
    return Padding(
      key: ValueKey('entry_${entry.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  khataKindLabel(tr, entry),
                  style: theme.textTheme.titleSmall,
                ),
                if (details.isNotEmpty) Text(details),
                Text(
                  '${formatDateTime(entry.at, language)} · ${entry.byName}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${addsDues ? '+' : '-'}${formatRupees(entry.amountPaise.abs())}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                tr('balance_after', {'amount': formatRupees(balanceAfter)}),
                style: theme.textTheme.bodySmall,
              ),
              if (canReverse)
                TextButton(
                  key: ValueKey('reverse_${entry.id}'),
                  onPressed: () => _reverse(context),
                  child: Text(tr('reverse_entry')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.customer});

  final Customer customer;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final amount = parseRupees(_amount.text)!;
    final customer = widget.customer;
    context.session.repository.recordPayment(
      customerId: customer.id,
      amountPaise: amount,
      method: _method,
      note: _note.text,
      clearDueDate: customer.hasDues && amount >= customer.balancePaise,
    );
    showMessage(
      context,
      tr('payment_recorded', {'amount': formatRupees(amount)}),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final customer = widget.customer;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('receive_payment'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AmountField(
            key: const Key('payment_amount'),
            controller: _amount,
            autofocus: true,
            big: true,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          if (customer.hasDues)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                key: const Key('payment_full'),
                label: Text(
                  tr('full_amount', {
                    'amount': formatRupees(customer.balancePaise),
                  }),
                ),
                onPressed: () => setState(
                  () => _amount.text = formatRupees(
                    customer.balancePaise,
                    symbol: false,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          MethodPicker(
            value: _method,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('note')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('payment_save'),
            onPressed: _save,
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}

class _CreditSheet extends StatefulWidget {
  const _CreditSheet({required this.customer});

  final Customer customer;

  @override
  State<_CreditSheet> createState() => _CreditSheetState();
}

class _CreditSheetState extends State<_CreditSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    context.session.repository.recordKhataPurchase(
      customerId: widget.customer.id,
      amountPaise: parseRupees(_amount.text)!,
      note: _note.text,
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr('record_credit'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(tr('record_credit_hint')),
          const SizedBox(height: 12),
          AmountField(
            key: const Key('credit_amount'),
            controller: _amount,
            autofocus: true,
            big: true,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('note')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('credit_save'),
            onPressed: _save,
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}

class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet({required this.customer});

  final Customer customer;

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _addToDues = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final amount = parseRupees(_amount.text)!;
    context.session.repository.recordAdjustment(
      customerId: widget.customer.id,
      signedPaise: _addToDues ? amount : -amount,
      note: _note.text,
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('adjustment'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(tr('adjustment_hint')),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(tr('reduce_dues'))),
              ButtonSegment(value: true, label: Text(tr('add_to_dues'))),
            ],
            selected: {_addToDues},
            onSelectionChanged: (s) => setState(() => _addToDues = s.first),
          ),
          const SizedBox(height: 12),
          AmountField(
            controller: _amount,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _note,
            decoration: InputDecoration(labelText: tr('reason')),
            validator: V.required(tr),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: Text(tr('save'))),
        ],
      ),
    );
  }
}
