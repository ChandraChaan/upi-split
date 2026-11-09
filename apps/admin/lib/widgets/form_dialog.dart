import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kirana_core/kirana_core.dart';

import '../utils/dates.dart';

/// Field validators; every message goes through the translator.
class Validators {
  const Validators(this.tr);
  final Tr tr;

  /// Keeps a mistyped amount well inside JavaScript's exact integer range.
  static const int _maxPaise = 100000000000;

  String? required(String? value) =>
      value == null || value.trim().isEmpty ? tr('required') : null;

  String? Function(String?) maxLength(int max, {bool isRequired = false}) => (value) {
        final text = value?.trim() ?? '';
        if (isRequired && text.isEmpty) return tr('required');
        return text.length > max ? tr('too_long', {'max': '$max'}) : null;
      };

  String? money(String? value) {
    final paise = parseRupees(value ?? '');
    if (paise == null || paise > _maxPaise) return tr('invalid_amount');
    return null;
  }

  String? positiveMoney(String? value) {
    final paise = parseRupees(value ?? '');
    if (paise == null || paise <= 0 || paise > _maxPaise) return tr('invalid_amount');
    return null;
  }

  String? optionalMoney(String? value) =>
      value == null || value.trim().isEmpty ? null : money(value);

  String? quantity(String? value) =>
      parseQuantity(value ?? '') == null ? tr('invalid_quantity') : null;

  /// A stock figure where zero is allowed.
  String? stock(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || RegExp(r'^0+(\.0{1,3})?$').hasMatch(text)) return null;
    return parseQuantity(text) == null ? tr('invalid_quantity') : null;
  }

  String? optionalPhone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return normalizeIndianPhone(value) == null ? tr('invalid_phone') : null;
  }

  String? email(String? value) {
    final text = value?.trim() ?? '';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text) ? null : tr('invalid_email');
  }

  String? newPassword(String? value) =>
      (value ?? '').length < 6 ? tr('password_too_short') : null;

  String? optionalGstin(String? value) {
    final text = value?.trim().toUpperCase() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^[0-9]{2}[A-Z0-9]{13}$').hasMatch(text) ? null : tr('invalid_gstin');
  }

  String? optionalUpi(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$').hasMatch(text) ? null : tr('invalid_upi');
  }
}

/// Keeps digits, one decimal point and commas in an amount field.
final moneyInputFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,₹]'));

sealed class FormSpec {
  const FormSpec(this.id);
  final String id;
}

class TextSpec extends FormSpec {
  const TextSpec(
    super.id,
    this.label, {
    this.initial = '',
    this.validator,
    this.keyboard,
    this.maxLines = 1,
    this.helper,
    this.suggestions = const [],
    this.formatters = const [],
  });
  final String label;
  final String initial;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;
  final int maxLines;
  final String? helper;
  final List<String> suggestions;
  final List<TextInputFormatter> formatters;
}

class ChoiceSpec extends FormSpec {
  const ChoiceSpec(super.id, this.label, this.options, {this.initial, this.required = true});
  final String label;
  final Map<String, String> options;
  final String? initial;
  final bool required;
}

class DateSpec extends FormSpec {
  const DateSpec(super.id, this.label, {required this.initial, required this.first, required this.last});
  final String label;
  final DateTime initial;
  final DateTime first;
  final DateTime last;
}

class SwitchSpec extends FormSpec {
  const SwitchSpec(super.id, this.label, {this.initial = false});
  final String label;
  final bool initial;
}

class MultiSpec extends FormSpec {
  const MultiSpec(super.id, this.label, this.options, {this.initial = const {}, this.minimum = 0});
  final String label;
  final Map<String, String> options;
  final Set<String> initial;
  final int minimum;
}

class FormValues {
  FormValues(this._text, this._choice, this._flag, this._multi, this._dates);
  final Map<String, String> _text;
  final Map<String, String?> _choice;
  final Map<String, bool> _flag;
  final Map<String, Set<String>> _multi;
  final Map<String, DateTime> _dates;

  String text(String id) => (_text[id] ?? '').trim();

  /// An amount that passed validation; a blank optional field is zero.
  int money(String id) => parseRupees(text(id)) ?? 0;

  /// A stock figure that passed validation; blank and "0" are zero.
  int stock(String id) => parseQuantity(text(id)) ?? 0;
  String? choice(String id) => _choice[id];
  bool flag(String id) => _flag[id] ?? false;
  Set<String> multi(String id) => _multi[id] ?? const {};
  DateTime date(String id) => _dates[id]!;
}

Future<FormValues?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FormSpec> specs,
  String? submitLabel,
  String? description,
  String? Function(FormValues values)? liveNotice,
}) =>
    showDialog<FormValues>(
      context: context,
      builder: (_) => FormDialog(
        title: title,
        specs: specs,
        submitLabel: submitLabel,
        description: description,
        liveNotice: liveNotice,
      ),
    );

class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.specs,
    this.submitLabel,
    this.description,
    this.liveNotice,
  });
  final String title;
  final List<FormSpec> specs;
  final String? submitLabel;
  final String? description;
  final String? Function(FormValues values)? liveNotice;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  final _form = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _choice = {};
  final Map<String, bool> _flag = {};
  final Map<String, Set<String>> _multi = {};
  final Map<String, DateTime> _dates = {};

  @override
  void initState() {
    super.initState();
    for (final spec in widget.specs) {
      switch (spec) {
        case TextSpec():
          _controllers[spec.id] = TextEditingController(text: spec.initial);
        case ChoiceSpec():
          _choice[spec.id] = spec.initial;
        case SwitchSpec():
          _flag[spec.id] = spec.initial;
        case MultiSpec():
          _multi[spec.id] = {...spec.initial};
        case DateSpec():
          _dates[spec.id] = spec.initial;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  FormValues get _values => FormValues(
        {for (final e in _controllers.entries) e.key: e.value.text},
        _choice,
        _flag,
        _multi,
        _dates,
      );

  void _submit() {
    if (_form.currentState?.validate() ?? false) Navigator.of(context).pop(_values);
  }

  Widget _text(TextSpec spec) {
    final controller = _controllers[spec.id]!;
    Widget field({TextEditingController? ctrl, FocusNode? focus}) => TextFormField(
          controller: ctrl ?? controller,
          focusNode: focus,
          decoration: InputDecoration(labelText: spec.label, helperText: spec.helper, helperMaxLines: 3),
          validator: spec.validator,
          keyboardType: spec.keyboard,
          maxLines: spec.maxLines,
          inputFormatters: spec.formatters,
          onChanged: widget.liveNotice == null ? null : (_) => setState(() {}),
        );
    if (spec.suggestions.isEmpty) return field();
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: _focusFor(spec.id),
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        return spec.suggestions.where((s) => s.toLowerCase().contains(q));
      },
      fieldViewBuilder: (context, ctrl, focus, onSubmit) => field(ctrl: ctrl, focus: focus),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(dense: true, title: Text(option), onTap: () => onSelected(option)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final Map<String, FocusNode> _focus = {};
  FocusNode _focusFor(String id) => _focus.putIfAbsent(id, FocusNode.new);

  Widget _dateField(DateSpec spec) => InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            firstDate: spec.first,
            lastDate: spec.last,
            initialDate: _dates[spec.id],
          );
          if (picked != null) setState(() => _dates[spec.id] = picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: spec.label,
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(formatDate(_dates[spec.id]!)),
        ),
      );

  Widget _choiceField(ChoiceSpec spec, Tr tr) => DropdownButtonFormField<String>(
        initialValue: _choice[spec.id],
        isExpanded: true,
        decoration: InputDecoration(labelText: spec.label),
        items: [
          for (final e in spec.options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        ],
        validator: (v) => spec.required && v == null ? tr('required') : null,
        onChanged: (v) => setState(() => _choice[spec.id] = v),
      );

  Widget _switchField(SwitchSpec spec) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(spec.label),
        value: _flag[spec.id]!,
        onChanged: (v) => setState(() => _flag[spec.id] = v),
      );

  Widget _multiField(MultiSpec spec, Tr tr) => FormField<Set<String>>(
        initialValue: _multi[spec.id],
        validator: (v) => (v?.length ?? 0) < spec.minimum ? tr('select_at_least_one') : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(spec.label, style: Theme.of(state.context).textTheme.labelLarge),
            for (final e in spec.options.entries)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(e.value),
                value: _multi[spec.id]!.contains(e.key),
                onChanged: (checked) {
                  setState(() {
                    if (checked ?? false) {
                      _multi[spec.id]!.add(e.key);
                    } else {
                      _multi[spec.id]!.remove(e.key);
                    }
                  });
                  state.didChange(_multi[spec.id]);
                },
              ),
            if (state.hasError)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(state.context).colorScheme.error, fontSize: 12),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final theme = Theme.of(context);
    final notice = widget.liveNotice?.call(_values);
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(widget.description!),
                ),
              for (final spec in widget.specs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: switch (spec) {
                    TextSpec() => _text(spec),
                    ChoiceSpec() => _choiceField(spec, tr),
                    SwitchSpec() => _switchField(spec),
                    MultiSpec() => _multiField(spec, tr),
                    DateSpec() => _dateField(spec),
                  },
                ),
              if (notice != null)
                Text(notice, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('cancel'))),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel ?? tr('save'))),
      ],
    );
  }
}

/// Asks for confirmation. Resolves to true only when the action was confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final tr = dialogContext.tr;
      final scheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: SizedBox(width: 460, child: Text(message)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(tr('cancel'))),
          FilledButton(
            style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return answer ?? false;
}

/// Choices for a store dropdown in a dialog.
Map<String, String> storeOptions(List<Store> stores) => {for (final s in stores) s.id: s.name};
