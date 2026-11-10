import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import '../widgets/customer_picker.dart';
import 'billing_screen.dart';

/// The counter: type or tap amounts and take the money, with no product list.
/// Small shops sell ₹1 and ₹2 items all day and have no time to pick each
/// one from a catalogue; [BillingScreen] is still there for itemised bills.
class SellScreen extends StatefulWidget {
  const SellScreen({super.key});

  @override
  State<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends State<SellScreen> {
  static const _quickRupees = [1, 2, 5, 10, 20, 50];

  final _tape = CounterTape();
  bool _busy = false;

  /// What the last sale did, with Undo for managers, until the next sale.
  String? _notice;
  CounterSale? _undoable;

  /// A key press. Starting the next sale ends the last one's Undo.
  void _update(void Function() change) => setState(() {
    change();
    _notice = null;
    _undoable = null;
  });

  Future<void> _sell(PaymentMethod method) async {
    final total = _tape.totalPaise;
    if (total == 0 || _busy) return;
    await _save(
      CounterPayment.settle(
        totalPaise: total,
        paidPaise: total,
        method: method,
      ),
      method,
    );
  }

  Future<void> _payLater() async {
    final total = _tape.totalPaise;
    if (total == 0 || _busy) return;
    final customer = await pickCustomer(context);
    if (customer == null || !mounted) return;
    final answer = await showSheet<PayLaterAnswer>(
      context,
      (_) => PayLaterSheet(totalPaise: total, customer: customer),
    );
    if (answer == null || !mounted) return;
    await _save(
      CounterPayment.settle(
        totalPaise: total,
        paidPaise: answer.paidPaise,
        method: answer.method,
      ),
      answer.method,
      customer: answer.customer,
    );
  }

  Future<void> _save(
    CounterPayment payment,
    PaymentMethod method, {
    Customer? customer,
  }) async {
    setState(() => _busy = true);
    final tr = context.trNow;
    final session = context.session;
    final canUndo = session.member?.role.canManage ?? false;
    final repo = session.repository;
    final number = await session.nextBillNumber();
    _tape.commit();
    final CounterSale sale;
    try {
      sale = repo.sellAtCounter(
        entries: List.of(_tape.entries),
        payment: payment,
        number: number,
        itemName: const Tr('en')('sell_line'),
        itemNameTe: const Tr('te')('sell_line'),
        customer: customer,
        method: method,
      );
    } on InvalidOperation {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, tr('error_generic'));
      }
      return;
    }
    final credit = payment.split.creditPaise;
    final message = credit > 0 && customer != null
        ? tr('sell_saved_khata', {
            'amount': formatRupees(credit),
            'name': customer.name,
          })
        : tr('sell_saved', {
            'amount': formatRupees(sale.bill.totalPaise),
            'method': methodLabel(tr, method),
          });
    if (!mounted) return;
    // Shown above the total rather than as a snackbar, which would cover
    // the pay buttons while the next customer waits.
    setState(() {
      _tape.takeAll();
      _busy = false;
      _notice = message;
      _undoable = canUndo ? sale : null;
    });
  }

  void _undo() {
    final sale = _undoable;
    if (sale == null) return;
    final tr = context.trNow;
    try {
      context.session.repository.undoCounterSale(
        sale,
        reason: tr('sell_undo_reason'),
      );
    } on InvalidOperation {
      return;
    }
    setState(() {
      _notice = tr('sell_undone');
      _undoable = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final enabled = !_tape.isEmpty && !_busy;
    return Scaffold(
      appBar: KiranaBar(
        title: tr('sell'),
        actions: [
          IconButton(
            key: const Key('sell_items'),
            tooltip: tr('sell_with_items'),
            icon: const Icon(Icons.list_alt),
            onPressed: () => push(context, const BillingScreen()),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Six rows of keys share what is left after about 200 points for
          // today's total, the amount and the gaps.
          final keyHeight = ((constraints.maxHeight - 200) / 6).clamp(
            32.0,
            60.0,
          );
          return _body(context, keyHeight, enabled);
        },
      ),
    );
  }

  Widget _body(BuildContext context, double keyHeight, bool enabled) {
    final tr = context.tr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _TodayStrip(),
          Expanded(
            child: _TapeView(
              tape: _tape,
              notice: _notice,
              onUndo: _undoable == null ? null : _undo,
              onRemove: (i) => _update(() => _tape.removeAt(i)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final r in _quickRupees)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: OutlinedButton(
                      key: ValueKey('quick_$r'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size(0, keyHeight),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _tape.isFull
                          ? null
                          : () => _update(() => _tape.add(r)),
                      child: FittedBox(
                        child: Text(
                          '₹$r',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _Keypad(
            keyHeight: keyHeight,
            onDigit: (d) => _update(() => _tape.digit(d)),
            onTimes: () => _update(_tape.multiply),
            onBackspace: () => _update(_tape.backspace),
            onClear: () => _update(_tape.clear),
            onAdd: () => _update(() => _tape.commit()),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _PayButton(
                key: const Key('sell_cash'),
                label: tr('cash'),
                icon: Icons.payments_outlined,
                color: KiranaColors.received,
                height: keyHeight + 8,
                onPressed: enabled ? () => _sell(PaymentMethod.cash) : null,
              ),
              const SizedBox(width: 8),
              _PayButton(
                key: const Key('sell_upi'),
                label: tr('upi'),
                icon: Icons.qr_code_2,
                color: Theme.of(context).colorScheme.primary,
                height: keyHeight + 8,
                onPressed: enabled ? () => _sell(PaymentMethod.upi) : null,
              ),
              const SizedBox(width: 8),
              _PayButton(
                key: const Key('sell_later'),
                label: tr('sell_pay_later'),
                icon: Icons.menu_book_outlined,
                color: KiranaColors.dues,
                height: keyHeight + 8,
                onPressed: enabled ? _payLater : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's takings, so the counter can see the day add up.
class _TodayStrip extends StatelessWidget {
  const _TodayStrip();

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final today = dayKey(DateTime.now());
    return Live<DayRollup>(
      id: today,
      stream: (repo) => repo.day(today),
      loading: const SizedBox(height: 28),
      builder: (context, day) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          tr('sell_today', {
            'amount': formatRupees(day.salesPaise),
            'count': '${day.billCount}',
          }),
          key: const Key('sell_today'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _TapeView extends StatelessWidget {
  const _TapeView({
    required this.tape,
    required this.onRemove,
    this.notice,
    this.onUndo,
  });

  final CounterTape tape;
  final ValueChanged<int> onRemove;
  final String? notice;
  final VoidCallback? onUndo;

  String _label(TapeEntry e) => e.count == 1
      ? formatRupees(e.pricePaise)
      : '${e.count} × ${formatRupees(e.pricePaise)}';

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final typed = tape.typed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < tape.entries.length; i++)
                  InputChip(
                    key: ValueKey('tape_$i'),
                    label: Text(_label(tape.entries[i])),
                    onDeleted: () => onRemove(i),
                    deleteButtonTooltipMessage: tr('sell_remove_amount', {
                      'amount': _label(tape.entries[i]),
                    }),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        ),
        if (typed.isNotEmpty)
          Text(
            '+ ₹${typed.replaceAll(CounterTape.times, ' × ')}',
            key: const Key('sell_typed'),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          )
        else if (tape.isEmpty && notice != null)
          Row(
            key: const Key('sell_notice'),
            children: [
              const Icon(
                Icons.check_circle,
                color: KiranaColors.received,
                size: 20,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  notice!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: KiranaColors.received,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onUndo != null)
                TextButton(
                  key: const Key('sell_undo'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: onUndo,
                  child: Text(tr('sell_undo')),
                ),
            ],
          )
        else if (tape.isEmpty)
          Text(
            tr('sell_hint'),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        SizedBox(
          height: 60,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatRupees(tape.totalPaise),
                key: const Key('sell_total'),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.keyHeight,
    required this.onDigit,
    required this.onTimes,
    required this.onBackspace,
    required this.onClear,
    required this.onAdd,
  });

  final double keyHeight;
  final ValueChanged<String> onDigit;
  final VoidCallback onTimes;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    Widget key(
      String id,
      Widget child,
      VoidCallback onTap, {
      int flex = 1,
      bool primary = false,
      String? tooltip,
    }) {
      final style = ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, keyHeight)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      final button = primary
          ? FilledButton(
              key: Key('key_$id'),
              style: style,
              onPressed: onTap,
              child: child,
            )
          : FilledButton.tonal(
              key: Key('key_$id'),
              style: style,
              onPressed: onTap,
              child: child,
            );
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: tooltip == null
              ? button
              : Tooltip(message: tooltip, child: button),
        ),
      );
    }

    Widget digit(String d) => key(
      d,
      Text(
        d,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
      () => onDigit(d),
    );

    return Column(
      children: [
        Row(
          children: [
            digit('1'),
            digit('2'),
            digit('3'),
            key(
              'back',
              const Icon(Icons.backspace_outlined),
              onBackspace,
              tooltip: tr('sell_delete'),
            ),
          ],
        ),
        Row(
          children: [
            digit('4'),
            digit('5'),
            digit('6'),
            key(
              'clear',
              Text(
                tr('sell_clear'),
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
              onClear,
            ),
          ],
        ),
        Row(
          children: [
            digit('7'),
            digit('8'),
            digit('9'),
            key(
              'times',
              const Text('×', style: TextStyle(fontSize: 26)),
              onTimes,
              tooltip: tr('sell_times'),
            ),
          ],
        ),
        Row(
          children: [
            digit('00'),
            digit('0'),
            key(
              'add',
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      tr('sell_add'),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
              onAdd,
              flex: 2,
              primary: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.height,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double height;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: Size(0, height),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the customer handed over for a "pay later" sale.
class PayLaterAnswer {
  const PayLaterAnswer({
    required this.customer,
    required this.paidPaise,
    required this.method,
  });
  final Customer customer;
  final int paidPaise;
  final PaymentMethod method;
}

/// Who is taking the goods on credit, and anything they paid now. Paying
/// less leaves the rest on their khata; paying more clears earlier dues.
class PayLaterSheet extends StatefulWidget {
  const PayLaterSheet({
    super.key,
    required this.totalPaise,
    required this.customer,
  });

  final int totalPaise;
  final Customer customer;

  @override
  State<PayLaterSheet> createState() => _PayLaterSheetState();
}

class _PayLaterSheetState extends State<PayLaterSheet> {
  final _paid = TextEditingController();
  late Customer _customer = widget.customer;
  PaymentMethod _method = PaymentMethod.cash;

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  bool get _invalid =>
      _paid.text.trim().isNotEmpty && parseRupees(_paid.text) == null;

  Future<void> _change() async {
    final picked = await pickCustomer(context);
    if (picked != null && mounted) setState(() => _customer = picked);
  }

  void _save() {
    if (_invalid) return;
    Navigator.pop(
      context,
      PayLaterAnswer(
        customer: _customer,
        paidPaise: parseRupeesOrZero(_paid.text),
        method: _method,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final paid = parseRupeesOrZero(_paid.text);
    final settled = CounterPayment.settle(
      totalPaise: widget.totalPaise,
      paidPaise: paid,
      method: _method,
    );
    final credit = settled.split.creditPaise;
    final duesAfter =
        _customer.balancePaise + credit - settled.towardsDuesPaise;
    final limit = _customer.creditLimitPaise;
    final overLimit = credit > 0 && limit > 0 && duesAfter > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_customer.name, style: theme.textTheme.titleLarge),
                  if (_customer.balancePaise != 0)
                    Text(
                      tr('current_dues', {
                        'amount': formatRupees(_customer.balancePaise),
                      }),
                    ),
                ],
              ),
            ),
            TextButton(
              key: const Key('paylater_change'),
              onPressed: _change,
              child: Text(tr('paylater_change')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LabelValue(
          tr('paylater_this_sale'),
          formatRupees(widget.totalPaise),
          strong: true,
        ),
        const SizedBox(height: 8),
        AmountField(
          key: const Key('paylater_paid'),
          controller: _paid,
          label: tr('paylater_paid_now'),
          onChanged: (_) => setState(() {}),
        ),
        if (_invalid)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('invalid_amount'),
              style: const TextStyle(color: KiranaColors.dues),
            ),
          ),
        if (paid > 0) ...[
          const SizedBox(height: 8),
          MethodPicker(
            value: _method,
            onChanged: (m) => setState(() => _method = m),
          ),
        ],
        const SizedBox(height: 8),
        if (credit > 0)
          LabelValue(
            tr('paylater_to_khata'),
            formatRupees(credit),
            color: KiranaColors.dues,
            strong: true,
          ),
        if (settled.towardsDuesPaise > 0)
          LabelValue(
            tr('paylater_off_dues'),
            formatRupees(settled.towardsDuesPaise),
            color: KiranaColors.received,
            strong: true,
          ),
        LabelValue(tr('paylater_dues_after'), formatRupees(duesAfter)),
        if (overLimit)
          Text(
            tr('credit_limit_warning', {'limit': formatRupees(limit)}),
            style: const TextStyle(
              color: KiranaColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('paylater_save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _invalid ? null : _save,
          child: Text(tr('save')),
        ),
      ],
    );
  }
}
