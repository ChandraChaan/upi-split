import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import '../widgets/customer_picker.dart';
import '../widgets/line_sheet.dart';
import 'receipt_screen.dart';

enum _PayMode { cash, upi, credit, split }

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.cart});

  final Cart cart;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _discount = TextEditingController();
  final _splitCash = TextEditingController();
  final _splitUpi = TextEditingController();
  final _splitCredit = TextEditingController();
  final _tendered = TextEditingController();
  _PayMode _mode = _PayMode.cash;
  Customer? _customer;
  bool _saving = false;
  bool _discountInvalid = false;

  Cart get _cart => widget.cart;

  @override
  void initState() {
    super.initState();
    if (_cart.discountPaise > 0) {
      _discount.text = formatRupees(_cart.discountPaise, symbol: false);
    }
  }

  @override
  void dispose() {
    _discount.dispose();
    _splitCash.dispose();
    _splitUpi.dispose();
    _splitCredit.dispose();
    _tendered.dispose();
    super.dispose();
  }

  bool _invalidMoney(TextEditingController c) =>
      c.text.trim().isNotEmpty && parseRupees(c.text) == null;

  bool get _splitInvalid =>
      _invalidMoney(_splitCash) ||
      _invalidMoney(_splitUpi) ||
      _invalidMoney(_splitCredit);

  PaymentSplit get _payment {
    final total = _cart.totalPaise;
    return switch (_mode) {
      _PayMode.cash => PaymentSplit(cashPaise: total),
      _PayMode.upi => PaymentSplit(upiPaise: total),
      _PayMode.credit => PaymentSplit(creditPaise: total),
      _PayMode.split => PaymentSplit(
        cashPaise: parseRupeesOrZero(_splitCash.text),
        upiPaise: parseRupeesOrZero(_splitUpi.text),
        creditPaise: parseRupeesOrZero(_splitCredit.text),
      ),
    };
  }

  void _onDiscountChanged(String text) {
    setState(() {
      final parsed = text.trim().isEmpty ? 0 : parseRupees(text);
      _discountInvalid = parsed == null;
      if (parsed != null) _cart.discountPaise = parsed;
      _rebalance();
    });
  }

  /// In a split, cash absorbs whatever UPI and credit do not cover.
  void _rebalance() {
    if (_mode != _PayMode.split) return;
    final rest =
        _cart.totalPaise -
        parseRupeesOrZero(_splitUpi.text) -
        parseRupeesOrZero(_splitCredit.text);
    _splitCash.text = rest > 0 ? formatRupees(rest, symbol: false) : '';
  }

  Future<void> _setMode(_PayMode mode) async {
    if (mode == _PayMode.credit && _customer == null) {
      final picked = await pickCustomer(context);
      if (picked == null || !mounted) return;
      _customer = picked;
    }
    setState(() {
      if (mode == _PayMode.split && _mode != _PayMode.split) {
        final current = _payment;
        String text(int paise) =>
            paise > 0 ? formatRupees(paise, symbol: false) : '';
        _splitCash.text = text(current.cashPaise);
        _splitUpi.text = text(current.upiPaise);
        _splitCredit.text = text(current.creditPaise);
      }
      _mode = mode;
    });
  }

  Future<void> _chooseCustomer() async {
    final picked = await pickCustomer(context);
    if (picked != null && mounted) setState(() => _customer = picked);
  }

  Future<void> _editLine(CartLine line, String title) async {
    final edit = await showSheet<LineEdit>(
      context,
      (_) => LineSheet(
        title: title,
        unit: line.unit,
        qtyMilli: line.qtyMilli,
        pricePaise: line.pricePaise,
        canRemove: true,
      ),
    );
    if (edit == null || !mounted) return;
    setState(() {
      applyLineEdit(_cart, line, edit);
      _rebalance();
    });
    if (_cart.isEmpty) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving) return;
    final tr = context.trNow;
    if (_discountInvalid) {
      showMessage(context, tr('invalid_amount'));
      return;
    }
    if (_mode == _PayMode.split && _splitInvalid) {
      showMessage(context, tr('invalid_amount'));
      return;
    }
    final payment = _payment;
    final customer = _customer;
    final problem = _cart.validate(payment, customer: customer);
    if (problem != null) {
      showMessage(context, switch (problem) {
        CartError.empty => tr('cart_empty'),
        CartError.tooManyLines => tr('cart_too_many'),
        CartError.invalidQuantity => tr('invalid_quantity'),
        CartError.discountTooLarge => tr('discount_too_large'),
        CartError.paymentMismatch => tr('payment_mismatch'),
        CartError.negativePayment => tr('invalid_amount'),
        CartError.creditNeedsCustomer => tr('credit_needs_customer'),
      });
      return;
    }
    if (customer != null &&
        payment.creditPaise > 0 &&
        _cart.exceedsCreditLimit(payment, customer)) {
      final proceed = await confirm(
        context,
        title: tr('credit_limit_title'),
        body: tr('credit_limit_body', {
          'name': customer.name,
          'limit': formatRupees(customer.creditLimitPaise),
          'after': formatRupees(customer.balancePaise + payment.creditPaise),
        }),
        action: tr('save_anyway'),
      );
      if (!proceed || !mounted) return;
    }
    _saving = true;
    final session = context.session;
    final navigator = Navigator.of(context);
    final repo = session.repository;
    final number = await session.nextBillNumber();
    final Bill bill;
    try {
      bill = repo.createBill(
        cart: _cart,
        payment: payment,
        number: number,
        customer: customer,
      );
    } on InvalidOperation {
      _saving = false;
      if (mounted) showMessage(context, tr('error_generic'));
      return;
    }
    _cart.clear();
    navigator
        .pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => ReceiptScreen(bill: bill, justSaved: true),
          ),
        )
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final theme = Theme.of(context);
    final payment = _payment;
    final customer = _customer;
    final total = _cart.totalPaise;
    final overLimit =
        customer != null &&
        payment.creditPaise > 0 &&
        _cart.exceedsCreditLimit(payment, customer);
    final discountTooLarge = _cart.discountPaise > _cart.subtotalPaise;
    final difference = total - payment.totalPaise;
    final tendered = parseRupeesOrZero(_tendered.text);

    return Scaffold(
      appBar: KiranaBar(title: tr('checkout')),
      body: ScrollColumn(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final line in _cart.lines)
                  InkWell(
                    onTap: () => _editLine(
                      line,
                      language == 'te' && line.nameTe.isNotEmpty
                          ? line.nameTe
                          : line.name,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  language == 'te' && line.nameTe.isNotEmpty
                                      ? line.nameTe
                                      : line.name,
                                  style: theme.textTheme.titleSmall,
                                ),
                                Text(
                                  '${formatQuantity(line.qtyMilli)} × ${formatRupees(line.pricePaise)}',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatRupees(line.totalPaise),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          LabelValue(tr('subtotal'), formatRupees(_cart.subtotalPaise)),
          const SizedBox(height: 4),
          TextFormField(
            key: const Key('checkout_discount'),
            controller: _discount,
            onChanged: _onDiscountChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('discount'),
              prefixText: '₹ ',
              errorText: _discountInvalid
                  ? tr('invalid_amount')
                  : discountTooLarge
                  ? tr('discount_too_large')
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(tr('total'), style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: BigNumber(
                    formatRupees(total),
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
              ),
            ],
          ),
          SectionTitle(tr('customer')),
          Card(
            child: ListTile(
              key: const Key('checkout_customer'),
              minTileHeight: 60,
              leading: const Icon(Icons.person_outline),
              title: Text(customer?.name ?? tr('choose_customer_optional')),
              subtitle: customer != null && customer.balancePaise != 0
                  ? Text(
                      tr('current_dues', {
                        'amount': formatRupees(customer.balancePaise),
                      }),
                    )
                  : null,
              trailing: customer == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(
                      tooltip: tr('remove_customer'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _customer = null;
                        if (_mode == _PayMode.credit) _mode = _PayMode.cash;
                      }),
                    ),
              onTap: _chooseCustomer,
            ),
          ),
          SectionTitle(tr('payment')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _modeChip(tr('all_cash'), _PayMode.cash, const Key('pay_cash')),
              _modeChip(tr('all_upi'), _PayMode.upi, const Key('pay_upi')),
              _modeChip(
                tr('all_credit'),
                _PayMode.credit,
                const Key('pay_credit'),
              ),
              _modeChip(
                tr('split_payment'),
                _PayMode.split,
                const Key('pay_split'),
              ),
            ],
          ),
          if (_mode == _PayMode.split) ...[
            const SizedBox(height: 12),
            AmountField(
              key: const Key('split_cash'),
              controller: _splitCash,
              label: tr('cash'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            AmountField(
              key: const Key('split_upi'),
              controller: _splitUpi,
              label: tr('upi'),
              onChanged: (_) => setState(_rebalance),
            ),
            const SizedBox(height: 10),
            AmountField(
              key: const Key('split_credit'),
              controller: _splitCredit,
              label: tr('credit'),
              onChanged: (_) => setState(_rebalance),
            ),
            if (_splitInvalid) ...[
              const SizedBox(height: 8),
              Text(
                tr('invalid_amount'),
                style: const TextStyle(color: KiranaColors.dues),
              ),
            ] else if (difference != 0) ...[
              const SizedBox(height: 8),
              Text(
                difference > 0
                    ? tr('payment_remaining', {
                        'amount': formatRupees(difference),
                      })
                    : tr('payment_excess', {
                        'amount': formatRupees(-difference),
                      }),
                style: const TextStyle(
                  color: KiranaColors.dues,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          if (payment.cashPaise > 0) ...[
            const SizedBox(height: 12),
            AmountField(
              key: const Key('cash_tendered'),
              controller: _tendered,
              label: tr('cash_received'),
              onChanged: (_) => setState(() {}),
            ),
            if (tendered > 0) ...[
              const SizedBox(height: 8),
              if (tendered >= payment.cashPaise)
                LabelValue(
                  tr('change_due'),
                  formatRupees(tendered - payment.cashPaise),
                  color: KiranaColors.received,
                  strong: true,
                )
              else
                LabelValue(
                  tr('cash_short'),
                  formatRupees(payment.cashPaise - tendered),
                  color: KiranaColors.dues,
                  strong: true,
                ),
            ],
          ],
          if (overLimit) ...[
            const SizedBox(height: 12),
            Card(
              color: KiranaColors.warning.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  tr('credit_limit_warning', {
                    'limit': formatRupees(customer.creditLimitPaise),
                  }),
                  style: const TextStyle(
                    color: KiranaColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          LabelValue(tr('payment_mode'), _summary(tr, payment)),
        ],
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('checkout_save'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _save,
          child: Text(tr('save_bill', {'amount': formatRupees(total)})),
        ),
      ),
    );
  }

  String _summary(Tr tr, PaymentSplit p) => [
    if (p.cashPaise > 0)
      '${methodLabel(tr, PaymentMethod.cash)} ${formatRupees(p.cashPaise)}',
    if (p.upiPaise > 0)
      '${methodLabel(tr, PaymentMethod.upi)} ${formatRupees(p.upiPaise)}',
    if (p.creditPaise > 0)
      '${methodLabel(tr, PaymentMethod.credit)} ${formatRupees(p.creditPaise)}',
  ].join(' + ');

  Widget _modeChip(String label, _PayMode mode, Key key) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: _mode == mode,
    onSelected: (_) => _setMode(mode),
  );
}
