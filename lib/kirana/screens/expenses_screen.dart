import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, this.openAdd = false});

  /// Home's quick action lands straight on the add form.
  final bool openAdd;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _monthView = false;

  @override
  void initState() {
    super.initState();
    if (widget.openAdd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _add();
      });
    }
  }

  void _add() => showSheet<void>(context, (_) => const _AddExpenseSheet());

  Future<void> _void(Expense e) async {
    final tr = context.trNow;
    final repo = context.session.repository;
    final ok = await confirm(
      context,
      title: tr('void_expense'),
      body: tr('void_expense_body', {'amount': formatRupees(e.amountPaise)}),
      action: tr('void_expense'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      repo.voidExpense(e);
      showMessage(context, tr('saved'));
    } on InvalidOperation {
      showMessage(context, tr('error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final today = dayKey(now);
    return Scaffold(
      appBar: KiranaBar(title: tr('expenses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('expense_add'),
        icon: const Icon(Icons.add),
        label: Text(tr('add_expense')),
        onPressed: _add,
      ),
      body: Live<List<Expense>>(
        id: monthStart,
        stream: (repo) => repo.expenses(from: monthStart, to: nextMonth),
        builder: (context, all) {
          final valid = all.where((e) => !e.voided);
          final todayTotal = valid
              .where((e) => e.dayKey == today)
              .fold<int>(0, (sum, e) => sum + e.amountPaise);
          final monthTotal = valid.fold<int>(
            0,
            (sum, e) => sum + e.amountPaise,
          );
          final list = _monthView
              ? all
              : all.where((e) => e.dayKey == today).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TwoColumn(
                  children: [
                    StatTile(
                      label: tr('today'),
                      value: formatRupees(todayTotal),
                    ),
                    StatTile(
                      label: tr('this_month'),
                      value: formatRupees(monthTotal),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(tr('today'))),
                    ButtonSegment(value: true, label: Text(tr('this_month'))),
                  ],
                  selected: {_monthView},
                  onSelectionChanged: (s) =>
                      setState(() => _monthView = s.first),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.account_balance_wallet_outlined,
                        message: tr('no_expenses'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = list[i];
                          return ListTile(
                            key: ValueKey('expense_${e.id}'),
                            minTileHeight: 64,
                            title: Text(expenseCategoryLabel(tr, e.category)),
                            subtitle: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  _monthView
                                      ? formatDateTime(e.at, language)
                                      : formatTime(e.at, language),
                                ),
                                Text(methodLabel(tr, e.method)),
                                if (e.note.isNotEmpty) Text(e.note),
                                if (e.voided)
                                  Flag(tr('voided'), color: KiranaColors.dues),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatRupees(e.amountPaise),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    decoration: e.voided
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                if (manager && !e.voided)
                                  IconButton(
                                    key: ValueKey('expense_void_${e.id}'),
                                    tooltip: tr('void_expense'),
                                    icon: const Icon(Icons.block),
                                    onPressed: () => _void(e),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet();

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  static const _customChoice = '__custom__';

  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _custom = TextEditingController();
  final _note = TextEditingController();
  String? _choice;
  PaymentMethod _method = PaymentMethod.cash;
  bool _showCategoryError = false;

  @override
  void dispose() {
    _amount.dispose();
    _custom.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _showCategoryError = _choice == null);
    if (!_form.currentState!.validate() || _choice == null) return;
    final tr = context.trNow;
    context.session.repository.addExpense(
      category: _choice == _customChoice ? _custom.text : _choice!,
      amountPaise: parseRupees(_amount.text)!,
      method: _method,
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
            tr('add_expense'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AmountField(
            key: const Key('expense_amount'),
            controller: _amount,
            autofocus: true,
            big: true,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          const SizedBox(height: 12),
          Text(tr('category'), style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final c in expenseCategories)
                ChoiceChip(
                  key: ValueKey('expense_cat_$c'),
                  label: Text(expenseCategoryLabel(tr, c)),
                  selected: _choice == c,
                  onSelected: (_) => setState(() {
                    _choice = c;
                    _showCategoryError = false;
                  }),
                ),
              ChoiceChip(
                key: const Key('expense_cat_custom'),
                label: Text(tr('exp_custom')),
                selected: _choice == _customChoice,
                onSelected: (_) => setState(() {
                  _choice = _customChoice;
                  _showCategoryError = false;
                }),
              ),
            ],
          ),
          if (_showCategoryError)
            Text(
              tr('choose_category'),
              style: const TextStyle(color: KiranaColors.dues),
            ),
          if (_choice == _customChoice) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('expense_custom'),
              controller: _custom,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('category')),
              validator: V.required(tr),
            ),
          ],
          const SizedBox(height: 12),
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
            key: const Key('expense_save'),
            onPressed: _save,
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}
