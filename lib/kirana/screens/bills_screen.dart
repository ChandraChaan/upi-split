import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:share_plus/share_plus.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'receipt_screen.dart';

/// Manager only. Asks for the required reason, then voids.
Future<void> askVoidBill(BuildContext context, Bill bill) async {
  final tr = context.trNow;
  final repo = context.session.repository;
  final reason = await showSheet<String>(
    context,
    (_) => _VoidReasonSheet(bill: bill),
  );
  if (reason == null || !context.mounted) return;
  try {
    repo.voidBill(bill, reason: reason);
    showMessage(context, tr('bill_voided'));
  } on InvalidOperation {
    showMessage(context, tr('error_generic'));
  }
}

class _VoidReasonSheet extends StatefulWidget {
  const _VoidReasonSheet({required this.bill});

  final Bill bill;

  @override
  State<_VoidReasonSheet> createState() => _VoidReasonSheetState();
}

class _VoidReasonSheetState extends State<_VoidReasonSheet> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
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
            tr('void_bill_title', {'number': widget.bill.number}),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(tr('void_bill_body')),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('void_reason'),
            controller: _reason,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('reason')),
            validator: V.required(tr),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('void_confirm'),
            style: FilledButton.styleFrom(backgroundColor: KiranaColors.dues),
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _reason.text.trim());
              }
            },
            child: Text(tr('void_bill')),
          ),
        ],
      ),
    );
  }
}

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  DateTime _day = startOfDay(DateTime.now());

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  bool get _isToday => _day == startOfDay(DateTime.now());

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _day = startOfDay(picked));
  }

  Future<void> _reshare(Bill bill) async {
    final tr = context.trNow;
    final session = context.session;
    final text = receiptText(
      language: session.language,
      store: session.store!,
      bill: bill,
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      debugPrint('Bill reshare failed: $e');
      if (mounted) showMessage(context, tr('share_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    final theme = Theme.of(context);
    final next = DateTime(_day.year, _day.month, _day.day + 1);
    return Scaffold(
      appBar: KiranaBar(title: tr('bills')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('bills_pick_date'),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _isToday ? tr('today') : formatDate(_day, language),
                    ),
                    onPressed: _pickDay,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isToday ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: Live<List<Bill>>(
              id: _day,
              stream: (repo) => repo.bills(from: _day, to: next),
              builder: (context, bills) {
                final valid = bills.where((b) => !b.voided);
                final total = valid.fold<int>(
                  0,
                  (sum, b) => sum + b.totalPaise,
                );
                if (bills.isEmpty) {
                  return EmptyState(
                    icon: Icons.receipt_outlined,
                    message: tr('no_bills'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: bills.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: LabelValue(
                          tr('bills_count', {'count': '${valid.length}'}),
                          formatRupees(total),
                          strong: true,
                        ),
                      );
                    }
                    final bill = bills[i - 1];
                    final amountStyle = theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      decoration: bill.voided
                          ? TextDecoration.lineThrough
                          : null,
                    );
                    return ListTile(
                      key: ValueKey('bill_${bill.id}'),
                      minTileHeight: 64,
                      title: Text(bill.number),
                      subtitle: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(formatTime(bill.at, language)),
                          if (bill.customerName.isNotEmpty)
                            Text(bill.customerName),
                          if (bill.voided)
                            Flag(tr('voided'), color: KiranaColors.dues),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatRupees(bill.totalPaise),
                            style: amountStyle,
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey('bill_menu_${bill.id}'),
                            onSelected: (value) {
                              if (value == 'share') _reshare(bill);
                              if (value == 'void') askVoidBill(context, bill);
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'share',
                                child: Text(tr('share')),
                              ),
                              if (manager && !bill.voided)
                                PopupMenuItem(
                                  value: 'void',
                                  child: Text(tr('void_bill')),
                                ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => push(context, ReceiptScreen(bill: bill)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
