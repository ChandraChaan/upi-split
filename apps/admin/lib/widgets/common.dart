import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../utils/combine.dart';
import '../utils/dates.dart';

const double kGap = 12;
const double kPagePadding = 24;

/// A value from one store's collection, with the store it came from.
class StoreItem<T> {
  const StoreItem(this.store, this.item);
  final Store store;
  final T item;
}

List<StoreItem<T>> flatten<T>(List<Store> stores, Map<String, List<T>> byStore) => [
      for (final store in stores)
        for (final item in byStore[store.id] ?? <T>[]) StoreItem<T>(store, item),
    ];

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Text for a code from an InvalidOperation.
String operationError(Tr tr, String code) => switch (code) {
      'name_required' => tr('op_name_required'),
      'amount_required' => tr('invalid_amount'),
      'invalid_method' => tr('op_invalid_method'),
      'cannot_reverse_reversal' => tr('op_cannot_reverse_reversal'),
      'void_the_bill_instead' => tr('op_void_the_bill_instead'),
      'manager_only' => tr('op_manager_only'),
      'quantity_required' => tr('invalid_quantity'),
      'already_voided' => tr('op_already_voided'),
      'reason_required' => tr('op_reason_required'),
      'invalid_paid' => tr('op_invalid_paid'),
      'too_many_lines' => tr('op_too_many_lines'),
      'category_required' => tr('op_category_required'),
      _ => tr('error_generic'),
    };

/// Runs a repository write, which returns at once, reporting local refusals.
/// Rejections from the server arrive later through SyncMonitor.failures.
void runWrite(BuildContext context, Tr tr, VoidCallback write, {String? done}) {
  try {
    write();
    if (done != null) showMessage(context, done);
  } on InvalidOperation catch (e) {
    showMessage(context, operationError(tr, e.code));
  }
}

/// Human name of a write, for the rejected-change message.
String writeLabel(Tr tr, String label) => switch (label) {
      'saveCustomer' => tr('write_save_customer'),
      'archiveCustomer' => tr('write_archive_customer'),
      'setDueDate' => tr('write_set_due_date'),
      'recordKhataPurchase' => tr('write_credit_purchase'),
      'recordPayment' => tr('write_payment'),
      'recordAdjustment' => tr('write_adjustment'),
      'reverseKhataEntry' => tr('write_reversal'),
      'logReminder' => tr('write_reminder'),
      'saveProduct' => tr('write_save_product'),
      'setProductActive' => tr('write_product_status'),
      'adjustStock' => tr('write_stock'),
      'voidBill' => tr('write_void_bill'),
      'addExpense' => tr('write_add_expense'),
      'voidExpense' => tr('write_void_expense'),
      'saveSupplier' => tr('write_save_supplier'),
      'archiveSupplier' => tr('write_archive_supplier'),
      'recordSupplierPurchase' => tr('write_supplier_purchase'),
      'recordSupplierPayment' => tr('write_supplier_payment'),
      'importProducts' => tr('write_import'),
      'copyCatalogue' => tr('write_copy_catalogue'),
      'addStore' || 'updateStore' => tr('write_store'),
      'updateMember' => tr('write_member'),
      'createInvite' => tr('write_invite'),
      'revokeInvite' => tr('write_revoke_invite'),
      'createBusiness' => tr('write_business'),
      _ => label,
    };

String unitLabel(Tr tr, Unit unit) => switch (unit) {
      Unit.piece => tr('unit_piece'),
      Unit.kg => tr('unit_kg'),
      Unit.litre => tr('unit_litre'),
      Unit.packet => tr('unit_packet'),
    };

String roleLabel(Tr tr, MemberRole role) => switch (role) {
      MemberRole.owner => tr('role_owner'),
      MemberRole.manager => tr('role_manager'),
      MemberRole.cashier => tr('role_cashier'),
    };

String methodLabel(Tr tr, PaymentMethod? method) => switch (method) {
      PaymentMethod.cash => tr('cash'),
      PaymentMethod.upi => tr('upi'),
      PaymentMethod.credit => tr('credit'),
      null => '-',
    };

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
}

/// Shown while the session starts; always offers a way out.
class SessionLoadingView extends StatelessWidget {
  const SessionLoadingView({super.key});
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    return Material(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(tr('loading')),
            if (session.user != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: session.signOut, child: Text(tr('sign_out'))),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, this.onRetry});
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Text(tr('error_generic'), textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: Text(tr('retry'))),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon = Icons.inbox_outlined, this.action});
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: color)),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

/// A StreamBuilder that keeps one subscription across rebuilds and only starts
/// a new one when [cacheKey] changes, with shared loading and error states.
class LiveBuilder<T> extends StatefulWidget {
  const LiveBuilder({
    super.key,
    required this.cacheKey,
    required this.create,
    required this.builder,
  });
  final Object cacheKey;
  final Stream<T> Function() create;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<LiveBuilder<T>> createState() => _LiveBuilderState<T>();
}

class _LiveBuilderState<T> extends State<LiveBuilder<T>> {
  Stream<T>? _stream;
  Object? _key;

  @override
  Widget build(BuildContext context) {
    if (_stream == null || _key != widget.cacheKey) {
      _key = widget.cacheKey;
      _stream = widget.create();
    }
    return StreamBuilder<T>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Stream error: ${snapshot.error}');
          return ErrorView(onRetry: () => setState(() => _stream = null));
        }
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const LoadingView();
        }
        final child = widget.builder(context, snapshot.data as T);
        // Previous results stay on screen, dimmed, while a new query loads.
        return snapshot.connectionState == ConnectionState.waiting
            ? Opacity(opacity: 0.55, child: child)
            : child;
      },
    );
  }
}

/// Subscribes to the same query in each store and hands over the latest
/// result per store id.
class StoreStreamBuilder<T> extends StatelessWidget {
  const StoreStreamBuilder({
    super.key,
    required this.stores,
    required this.cacheKey,
    required this.source,
    required this.builder,
  });
  final List<Store> stores;
  final String cacheKey;
  final Stream<T> Function(StoreRepository repo) source;
  final Widget Function(BuildContext context, Map<String, T> byStore) builder;

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionController>(context, listen: false);
    final actor = session.actor;
    final business = session.business;
    if (actor == null || business == null) return const SizedBox.shrink();
    final ids = stores.map((s) => s.id).join(',');
    return LiveBuilder<Map<String, T>>(
      cacheKey: '${business.id}|${actor.uid}|${actor.role.name}|$ids|$cacheKey',
      create: () => combineLatestMap<String, T>({
        for (final s in stores) s.id: source(session.repositoryFor(s.id)),
      }),
      builder: builder,
    );
  }
}

/// Title row, filter row and scrolling content, used by every page.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.actions = const [],
    this.filters = const [],
  });
  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : kPagePadding;
    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (onBack != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: kGap),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (filters.isNotEmpty) ...[
            const SizedBox(height: kGap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: filters,
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: TextField(
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            prefixIcon: const Icon(Icons.search),
          ),
        ),
      );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing});
  final String? title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(title!, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: kGap),
              ],
              child,
            ],
          ),
        ),
      );
}

/// One headline figure. The value shrinks rather than breaking across lines.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color, this.icon});
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 4)],
              Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lays tiles out in equal columns that fit the width available.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.minTileWidth = 132});
  final List<Widget> children;
  final double minTileWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        const spacing = 16.0;
        final width = constraints.maxWidth;
        final columns = ((width + spacing) / (minTileWidth + spacing)).floor().clamp(1, 8);
        final tile = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final c in children) SizedBox(width: tile, child: c)],
        );
      });
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, size: icon == null ? 8 : 16, color: color),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: TextStyle(color: color, fontSize: 13))),
        ],
      );
}

/// A date filter: preset chips plus a custom range picker.
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({
    super.key,
    required this.preset,
    required this.range,
    required this.onChanged,
    this.presets = const [
      RangePreset.today,
      RangePreset.yesterday,
      RangePreset.thisWeek,
      RangePreset.last7,
      RangePreset.thisMonth,
      RangePreset.lastMonth,
      RangePreset.last30,
    ],
  });
  final RangePreset preset;
  final DateRange range;
  final List<RangePreset> presets;
  final void Function(RangePreset preset, DateRange range) onChanged;

  String _label(Tr tr, RangePreset p) => switch (p) {
        RangePreset.today => tr('today'),
        RangePreset.yesterday => tr('yesterday'),
        RangePreset.thisWeek => tr('this_week'),
        RangePreset.last7 => tr('last_7_days'),
        RangePreset.thisMonth => tr('this_month'),
        RangePreset.lastMonth => tr('last_month'),
        RangePreset.last30 => tr('last_30_days'),
        RangePreset.custom => tr('custom_range'),
      };

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final p in presets)
          ChoiceChip(
            label: Text(_label(tr, p)),
            selected: preset == p,
            onSelected: (_) => onChanged(p, presetRange(p, DateTime.now())),
          ),
        ChoiceChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(preset == RangePreset.custom
              ? '${formatDate(range.start)} - ${formatDate(range.end)}'
              : tr('custom_range')),
          selected: preset == RangePreset.custom,
          onSelected: (_) async {
            final now = DateTime.now();
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: now,
              initialDateRange: DateTimeRange(start: range.start, end: range.end),
            );
            if (picked != null) {
              onChanged(RangePreset.custom, DateRange(picked.start, picked.end));
            }
          },
        ),
      ],
    );
  }
}

/// A short line of muted text.
class Muted extends StatelessWidget {
  const Muted(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }
}

class NotFoundBody extends StatelessWidget {
  const NotFoundBody({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    return EmptyState(
      icon: Icons.search_off,
      message: tr('not_found'),
      action: TextButton(onPressed: onBack, child: Text(tr('go_back'))),
    );
  }
}
