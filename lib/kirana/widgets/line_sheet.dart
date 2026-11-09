import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import 'common.dart';

class LineEdit {
  const LineEdit({
    required this.qtyMilli,
    required this.pricePaise,
    this.remove = false,
  });
  const LineEdit.remove() : qtyMilli = 0, pricePaise = 0, remove = true;
  final int qtyMilli;
  final int pricePaise;
  final bool remove;
}

void applyLineEdit(Cart cart, CartLine line, LineEdit edit) {
  if (edit.remove) {
    cart.lines.remove(line);
  } else {
    line.qtyMilli = edit.qtyMilli;
    line.pricePaise = edit.pricePaise;
  }
}

/// Quantity (decimals allowed) and price for one line of the bill.
class LineSheet extends StatefulWidget {
  const LineSheet({
    super.key,
    required this.title,
    required this.unit,
    required this.pricePaise,
    this.qtyMilli,
    this.canRemove = false,
  });

  final String title;
  final Unit unit;
  final int pricePaise;
  final int? qtyMilli;
  final bool canRemove;

  @override
  State<LineSheet> createState() => _LineSheetState();
}

class _LineSheetState extends State<LineSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late final TextEditingController _price;

  static const _presets = [250, 500, 1000, 2000, 5000];

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: widget.qtyMilli == null ? '' : formatQuantity(widget.qtyMilli!),
    );
    _price = TextEditingController(
      text: formatRupees(widget.pricePaise, symbol: false),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      LineEdit(
        qtyMilli: parseQuantity(_qty.text)!,
        pricePaise: parseRupees(_price.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final unit = unitLabel(tr, widget.unit);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          QuantityField(
            key: const Key('line_qty'),
            controller: _qty,
            autofocus: widget.qtyMilli == null,
            label: tr('quantity_in', {'unit': unit}),
            validator: V.quantity(tr),
          ),
          if (isLooseUnit(widget.unit)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final milli in _presets)
                  ActionChip(
                    label: Text(formatQuantity(milli)),
                    onPressed: () =>
                        setState(() => _qty.text = formatQuantity(milli)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          AmountField(
            key: const Key('line_price'),
            controller: _price,
            label: tr('price_per', {'unit': unit}),
            validator: V.price(tr),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('line_done'),
            onPressed: _done,
            child: Text(tr('done')),
          ),
          if (widget.canRemove) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('line_remove'),
              style: TextButton.styleFrom(foregroundColor: KiranaColors.dues),
              onPressed: () => Navigator.pop(context, const LineEdit.remove()),
              child: Text(tr('remove_item')),
            ),
          ],
        ],
      ),
    );
  }
}

class CustomLine {
  const CustomLine(this.name, this.pricePaise, this.qtyMilli);
  final String name;
  final int pricePaise;
  final int qtyMilli;
}

/// A one-off item that is not in the catalogue and has no stock to reduce.
class CustomLineSheet extends StatefulWidget {
  const CustomLineSheet({super.key});

  @override
  State<CustomLineSheet> createState() => _CustomLineSheetState();
}

class _CustomLineSheetState extends State<CustomLineSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _done() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      CustomLine(
        _name.text.trim(),
        parseRupees(_price.text)!,
        parseQuantity(_qty.text)!,
      ),
    );
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
            tr('custom_item'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('custom_name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: tr('item_name')),
            validator: V.required(tr),
          ),
          const SizedBox(height: 12),
          AmountField(
            key: const Key('custom_price'),
            controller: _price,
            label: tr('amount'),
            validator: V.amount(tr),
          ),
          const SizedBox(height: 12),
          QuantityField(
            controller: _qty,
            label: tr('quantity'),
            validator: V.quantity(tr),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('custom_done'),
            onPressed: _done,
            child: Text(tr('add')),
          ),
        ],
      ),
    );
  }
}
