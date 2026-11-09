import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../widgets/common.dart';

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _address = TextEditingController(
    text: widget.customer?.address ?? '',
  );
  late final _limit = TextEditingController(
    text: (widget.customer?.creditLimitPaise ?? 0) > 0
        ? formatRupees(widget.customer!.creditLimitPaise, symbol: false)
        : '',
  );

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final session = context.session;
    final canManage = session.member?.role.canManage ?? false;
    // A cashier may fix a name or phone; the limit stays as a manager set it.
    final limit = canManage
        ? parseRupeesOrZero(_limit.text)
        : (widget.customer?.creditLimitPaise ?? 0);
    try {
      session.repository.saveCustomer(
        id: widget.customer?.id,
        name: _name.text,
        phone: _phone.text,
        address: _address.text,
        creditLimitPaise: limit,
      );
    } on InvalidOperation {
      showMessage(context, tr('error_generic'));
      return;
    }
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final manager = context.canManage;
    return Scaffold(
      appBar: KiranaBar(
        title: widget.customer == null
            ? tr('add_customer')
            : tr('edit_customer'),
      ),
      body: Form(
        key: _form,
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('customer_name'),
              controller: _name,
              autofocus: widget.customer == null,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('name')),
              validator: V.required(tr),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('customer_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('phone')),
              validator: V.phone(tr),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: InputDecoration(labelText: tr('address')),
            ),
            if (manager) ...[
              const SizedBox(height: 12),
              AmountField(
                key: const Key('customer_limit'),
                controller: _limit,
                label: tr('credit_limit'),
                validator: V.amount(tr, optional: true),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  tr('credit_limit_hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('customer_save'),
          onPressed: _save,
          child: Text(tr('save')),
        ),
      ),
    );
  }
}
