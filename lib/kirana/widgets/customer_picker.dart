import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import 'common.dart';

Future<Customer?> pickCustomer(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: const FractionallySizedBox(
        heightFactor: 0.85,
        child: _CustomerPicker(),
      ),
    ),
  );
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _form = GlobalKey<FormState>();
  final _query = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _query.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _quickAdd() {
    if (!_form.currentState!.validate()) return;
    final repo = context.session.repository;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final id = repo.saveCustomer(name: name, phone: phone);
    Navigator.pop(context, Customer(id: id, name: name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    if (_adding) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('new_customer'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('quick_customer_name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('name')),
                validator: V.required(tr),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('quick_customer_phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: tr('phone')),
                validator: V.phone(tr),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('quick_customer_save'),
                onPressed: _quickAdd,
                child: Text(tr('save')),
              ),
              TextButton(
                onPressed: () => setState(() => _adding = false),
                child: Text(tr('back_to_list')),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('customer_picker_search'),
            controller: _query,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: tr('customer_search_hint'),
              prefixIcon: const Icon(Icons.search),
            ),
          ),
        ),
        ListTile(
          key: const Key('quick_add_customer'),
          leading: const Icon(Icons.person_add_alt),
          title: Text(tr('new_customer')),
          onTap: () => setState(() {
            _name.text = int.tryParse(_query.text.trim()) == null
                ? _query.text.trim()
                : '';
            _phone.text = int.tryParse(_query.text.trim()) == null
                ? ''
                : _query.text.trim();
            _adding = true;
          }),
        ),
        const Divider(height: 1),
        Expanded(
          child: Live<List<Customer>>(
            stream: (repo) => repo.customers(),
            builder: (context, customers) {
              final q = _query.text.trim().toLowerCase();
              final list = customers
                  .where(
                    (c) =>
                        c.name.toLowerCase().contains(q) || c.phone.contains(q),
                  )
                  .toList();
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.person_search,
                  message: tr('no_matches'),
                );
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    key: ValueKey('pick_customer_${c.id}'),
                    title: Text(c.name),
                    subtitle: c.phone.isEmpty ? null : Text(c.phone),
                    trailing: c.hasDues
                        ? Text(
                            formatRupees(c.balancePaise),
                            style: const TextStyle(
                              color: KiranaColors.dues,
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : null,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
