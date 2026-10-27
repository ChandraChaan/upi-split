import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:upi_kit/upi_kit.dart';

/// A rupee amount field that reports whole paise, or null while the text
/// isn't a valid amount.
class AmountField extends StatefulWidget {
  const AmountField({
    super.key,
    required this.paise,
    required this.onChanged,
    this.label,
    this.fieldKey,
  });

  final int paise;
  final ValueChanged<int> onChanged;
  final String? label;
  final Key? fieldKey;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final _controller = TextEditingController(
    text: widget.paise == 0 ? '' : _text(widget.paise),
  );
  String? _error;

  static String _text(int paise) {
    final formatted = UpiAmount.paise(paise).format();
    return formatted.endsWith('.00')
        ? formatted.substring(0, formatted.length - 3)
        : formatted;
  }

  @override
  void didUpdateWidget(AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = UpiAmount.tryParse(_controller.text)?.paise ?? 0;
    if (widget.paise != current && _error == null) {
      _controller.text = widget.paise == 0 ? '' : _text(widget.paise);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: widget.label,
        prefixText: '₹ ',
        errorText: _error,
      ),
      onChanged: (text) {
        if (text.trim().isEmpty) {
          setState(() => _error = null);
          widget.onChanged(0);
          return;
        }
        final amount = UpiAmount.tryParse(text);
        setState(() => _error = amount == null ? 'Like 240 or 240.50' : null);
        if (amount != null) widget.onChanged(amount.paise);
      },
    );
  }
}

/// A titled card section.
class Section extends StatelessWidget {
  const Section({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what copied')));
}
