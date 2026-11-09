import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../utils/csv.dart';
import '../utils/dates.dart';
import 'common.dart';

/// One column of an [AdminTable]: how to show it, sort it and export it.
class TableCol<T> {
  const TableCol(this.label, this.cell, {this.sortKey, this.numeric = false, this.csv});

  factory TableCol.text(
    String label,
    String Function(T row) value, {
    double maxWidth = 280,
    bool sortable = true,
  }) =>
      TableCol<T>(
        label,
        (row) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Text(value(row)),
        ),
        sortKey: sortable ? (row) => value(row).toLowerCase() : null,
        csv: value,
      );

  factory TableCol.money(String label, int Function(T row) paise, {Color? Function(T row)? color}) =>
      TableCol<T>(
        label,
        (row) => Text(formatRupees(paise(row)), style: TextStyle(color: color?.call(row))),
        sortKey: paise,
        numeric: true,
        csv: (row) => csvMoney(paise(row)),
      );

  factory TableCol.qty(String label, int Function(T row) milli) => TableCol<T>(
        label,
        (row) => Text(formatQuantity(milli(row))),
        sortKey: milli,
        numeric: true,
        csv: (row) => formatQuantity(milli(row)),
      );

  factory TableCol.dateTime(String label, DateTime? Function(T row) value) => TableCol<T>(
        label,
        (row) => Text(value(row) == null ? '-' : formatDateTime(value(row)!)),
        sortKey: value,
        csv: (row) => value(row) == null ? '' : formatDateTime(value(row)!),
      );

  factory TableCol.date(String label, DateTime? Function(T row) value) => TableCol<T>(
        label,
        (row) => Text(value(row) == null ? '-' : formatDate(value(row)!)),
        sortKey: value,
        csv: (row) => value(row) == null ? '' : formatDate(value(row)!),
      );

  final String label;
  final Widget Function(T row) cell;
  final Object? Function(T row)? sortKey;
  final bool numeric;

  /// Value for CSV export; columns without one, like actions, are left out.
  final Object? Function(T row)? csv;
}

/// Header and rows ready for [buildCsv].
List<List<Object?>> tableCsvRows<T>(List<TableCol<T>> columns, Iterable<T> rows) {
  final exported = columns.where((c) => c.csv != null).toList();
  return [
    [for (final c in exported) c.label],
    for (final row in rows) [for (final c in exported) c.csv!(row)],
  ];
}

int _compareKeys(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return (a as Comparable<Object?>).compareTo(b);
}

/// A sortable, paged data table that scrolls sideways inside its own box, so
/// the page itself never scrolls horizontally. Rows grow to fit wrapped text.
class AdminTable<T> extends StatefulWidget {
  const AdminTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
    this.onTap,
    this.sortColumn,
    this.ascending = true,
    this.pageSize = 50,
    this.totalRow,
  });

  final List<TableCol<T>> columns;
  final List<T> rows;
  final String emptyMessage;
  final void Function(T row)? onTap;
  final int? sortColumn;
  final bool ascending;
  final int pageSize;

  /// Pinned below the last row whatever the sort order, shown in bold.
  final T? totalRow;

  @override
  State<AdminTable<T>> createState() => _AdminTableState<T>();
}

class _AdminTableState<T> extends State<AdminTable<T>> {
  final _scroll = ScrollController();
  late int? _sortColumn = widget.sortColumn;
  late bool _ascending = widget.ascending;
  int _page = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  DataRow _row(T row, {bool bold = false}) => DataRow(
        onSelectChanged:
            widget.onTap == null || bold ? null : (_) => widget.onTap!(row),
        cells: [
          for (final c in widget.columns)
            DataCell(bold
                ? DefaultTextStyle.merge(
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    child: c.cell(row),
                  )
                : c.cell(row)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    if (widget.rows.isEmpty) return Card(child: EmptyState(message: widget.emptyMessage));

    final sorted = List<T>.of(widget.rows);
    // Columns can come and go when the store selection changes.
    final sortColumn =
        _sortColumn != null && _sortColumn! < widget.columns.length ? _sortColumn : null;
    final key = sortColumn == null ? null : widget.columns[sortColumn].sortKey;
    if (key != null) {
      sorted.sort((a, b) {
        final result = _compareKeys(key(a), key(b));
        return _ascending ? result : -result;
      });
    }
    final pageCount = (sorted.length / widget.pageSize).ceil();
    final page = _page.clamp(0, pageCount - 1);
    final start = page * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, sorted.length);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    columnSpacing: 24,
                    horizontalMargin: 16,
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: double.infinity,
                    sortColumnIndex: key == null ? null : sortColumn,
                    sortAscending: _ascending,
                    columns: [
                      for (var i = 0; i < widget.columns.length; i++)
                        DataColumn(
                          label: Text(widget.columns[i].label, softWrap: false),
                          numeric: widget.columns[i].numeric,
                          onSort: widget.columns[i].sortKey == null
                              ? null
                              : (index, ascending) => setState(() {
                                    _sortColumn = index;
                                    _ascending = ascending;
                                    _page = 0;
                                  }),
                        ),
                    ],
                    rows: [
                      for (final row in sorted.sublist(start, end)) _row(row),
                      if (widget.totalRow != null) _row(widget.totalRow as T, bold: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(tr('table_page', {
                    'from': '${start + 1}',
                    'to': '$end',
                    'total': '${sorted.length}',
                  })),
                  IconButton(
                    onPressed: page == 0 ? null : () => setState(() => _page = page - 1),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: tr('previous_page'),
                  ),
                  IconButton(
                    onPressed:
                        page >= pageCount - 1 ? null : () => setState(() => _page = page + 1),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: tr('next_page'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
