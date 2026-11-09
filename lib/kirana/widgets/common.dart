import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

/// The selected store's repository, or null while the session is not ready.
StoreRepository? repoOf(SessionController s) =>
    s.stage == SessionStage.ready && s.business != null && s.store != null
    ? s.repository
    : null;

extension SessionContext on BuildContext {
  SessionController get session => read<SessionController>();

  /// Use in event handlers. context.tr is a build-time lookup and asserts there.
  Tr get trNow => Tr(read<SessionController>().language);

  String get lang => select<SessionController, String>((s) => s.language);

  bool get canManage =>
      select<SessionController, bool>((s) => s.member?.role.canManage ?? false);
}

Future<void> push(BuildContext context, Widget screen) => Navigator.of(
  context,
).push<void>(MaterialPageRoute<void>(builder: (_) => screen));

void showMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// A scrolling bottom sheet that stays above the keyboard.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Builder(builder: builder),
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String action,
  bool destructive = false,
}) async {
  final tr = context.trNow;
  final answer = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr('cancel')),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: KiranaColors.dues)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}

class V {
  static FormFieldValidator<String> required(Tr tr) =>
      (v) => v == null || v.trim().isEmpty ? tr('required') : null;

  /// A positive rupee amount. With [optional], blank and zero are also fine.
  static FormFieldValidator<String> amount(Tr tr, {bool optional = false}) =>
      (v) {
        final text = v?.trim() ?? '';
        if (text.isEmpty) return optional ? null : tr('required');
        final paise = parseRupees(text);
        if (paise == null || (!optional && paise == 0)) {
          return tr('invalid_amount');
        }
        return null;
      };

  /// A rupee amount that must be entered but may be zero, as for a free item.
  static FormFieldValidator<String> price(Tr tr) => (v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return tr('required');
    return parseRupees(text) == null ? tr('invalid_amount') : null;
  };

  static FormFieldValidator<String> quantity(Tr tr, {bool optional = false}) =>
      (v) {
        final text = v?.trim() ?? '';
        if (text.isEmpty) return optional ? null : tr('required');
        if (optional && parseQuantityOrZero(text) != null) return null;
        return parseQuantity(text) == null ? tr('invalid_quantity') : null;
      };

  /// GSTIN is optional, but what is entered must have the 15-character shape.
  static FormFieldValidator<String> gstin(Tr tr) => (v) {
    final text = v?.trim().toUpperCase() ?? '';
    if (text.isEmpty) return null;
    return RegExp(r'^\d{2}[A-Z0-9]{13}$').hasMatch(text)
        ? null
        : tr('invalid_gstin');
  };

  /// Phone is optional, but what is entered must be a usable mobile number.
  static FormFieldValidator<String> phone(Tr tr) => (v) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return null;
    return normalizeIndianPhone(text) == null ? tr('invalid_phone') : null;
  };
}

int? parseQuantityOrZero(String text) {
  final t = text.trim();
  if (t.isEmpty || RegExp(r'^0*\.?0*$').hasMatch(t)) return 0;
  return parseQuantity(t);
}

int parseRupeesOrZero(String text) =>
    text.trim().isEmpty ? 0 : (parseRupees(text) ?? 0);

/// Text input for rupees. Empty text means no amount.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.big = false,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      validator: validator,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: big ? Theme.of(context).textTheme.headlineSmall : null,
      decoration: InputDecoration(labelText: label, prefixText: '₹ '),
    );
  }
}

/// Text input for a quantity, with decimals for loose goods.
class QuantityField extends StatelessWidget {
  const QuantityField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      validator: validator,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(labelText: label),
    );
  }
}

class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncMonitor>();
    final tr = context.tr;
    final state = sync.state;
    final pending = sync.pendingWrites;
    final (IconData icon, Color color, String message) = switch (state) {
      SyncState.synced => (
        Icons.cloud_done_outlined,
        KiranaColors.received,
        tr('sync_synced'),
      ),
      SyncState.syncing => (
        Icons.cloud_upload_outlined,
        KiranaColors.warning,
        pending > 0
            ? tr('sync_pending', {'count': '$pending'})
            : tr('sync_syncing'),
      ),
      SyncState.offline => (
        Icons.cloud_off_outlined,
        KiranaColors.dues,
        tr('sync_offline'),
      ),
    };
    return Semantics(
      label: message,
      button: true,
      child: InkWell(
        key: const Key('sync_badge'),
        borderRadius: BorderRadius.circular(24),
        onTap: () => showMessage(context, message),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 22),
                if (state == SyncState.syncing && pending > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$pending',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KiranaBar extends StatelessWidget implements PreferredSizeWidget {
  const KiranaBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [...actions, const SyncBadge(), const SizedBox(width: 4)],
      bottom: bottom,
    );
  }
}

/// A repository stream with loading and error states. The stream is created
/// once per store and [id], so a rebuild never re-subscribes.
class Live<T> extends StatefulWidget {
  const Live({
    super.key,
    required this.stream,
    required this.builder,
    this.id,
    this.loading,
  });

  final Stream<T> Function(StoreRepository repo) stream;
  final Widget Function(BuildContext context, T data) builder;
  final Object? id;
  final Widget? loading;

  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  StoreRepository? _repo;
  Object? _id;
  Stream<T>? _stream;

  @override
  Widget build(BuildContext context) {
    final repo = context.select<SessionController, StoreRepository?>(repoOf);
    if (repo == null) return const SizedBox.shrink();
    if (_stream == null || !identical(repo, _repo) || widget.id != _id) {
      _repo = repo;
      _id = widget.id;
      _stream = widget.stream(repo);
    }
    return StreamBuilder<T>(
      key: ObjectKey(_stream),
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Stream error: ${snapshot.error}');
          return ErrorState(onRetry: () => setState(() => _stream = null));
        }
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return widget.loading ?? const LoadingState();
        }
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: CircularProgressIndicator(),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return EmptyState(
      icon: Icons.error_outline,
      message: tr('error_generic'),
      actionLabel: tr('retry'),
      onAction: onRetry,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Label on the left, value on the right; both wrap.
class LabelValue extends StatelessWidget {
  const LabelValue(
    this.label,
    this.value, {
    super.key,
    this.color,
    this.strong = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final base = strong
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: base)),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: base?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A number that shrinks instead of overflowing.
class BigNumber extends StatelessWidget {
  const BigNumber(this.text, {super.key, this.color, this.style});

  final String text;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleLarge;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: base?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              BigNumber(value, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays children out two to a row, each row as tall as its tallest tile.
class TwoColumn extends StatelessWidget {
  const TwoColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: children[i]),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < children.length
                      ? children[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class Bar extends StatelessWidget {
  const Bar({super.key, required this.fraction, this.color});

  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: LinearProgressIndicator(
        value: fraction.clamp(0.0, 1.0),
        minHeight: 10,
        color: color,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class Flag extends StatelessWidget {
  const Flag(this.text, {super.key, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return SegmentedButton<String>(
      key: const Key('language_toggle'),
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 'te', label: Text(tr('telugu'))),
        ButtonSegment(value: 'en', label: Text(tr('english'))),
      ],
      selected: {context.lang},
      onSelectionChanged: (selection) =>
          context.session.setLanguage(selection.first),
    );
  }
}

/// Hides a screen from a member demoted while it was open.
class ManagerOnly extends StatelessWidget {
  const ManagerOnly({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.canManage) return child;
    final tr = context.tr;
    return Scaffold(
      appBar: AppBar(),
      body: EmptyState(icon: Icons.lock_outline, message: tr('managers_only')),
    );
  }
}

/// Full-width primary action pinned above the system navigation area.
class BottomAction extends StatelessWidget {
  const BottomAction({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: child,
      ),
    );
  }
}

/// Cash or UPI; credit is never a way to settle money.
class MethodPicker extends StatelessWidget {
  const MethodPicker({super.key, required this.value, required this.onChanged});

  final PaymentMethod value;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return SegmentedButton<PaymentMethod>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: PaymentMethod.cash, label: Text(tr('cash'))),
        ButtonSegment(value: PaymentMethod.upi, label: Text(tr('upi'))),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// A scrolling column for forms and dashboards. Unlike a ListView it keeps
/// every child built, so Form.validate sees fields scrolled out of view and
/// live sections do not re-subscribe.
class ScrollColumn extends StatelessWidget {
  const ScrollColumn({super.key, this.padding, required this.children});

  final EdgeInsetsGeometry? padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
