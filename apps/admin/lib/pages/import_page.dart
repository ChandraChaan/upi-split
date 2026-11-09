import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../data/catalogue_writer.dart';
import '../store_scope.dart';
import '../utils/csv.dart';
import '../utils/platform.dart';
import '../utils/product_import.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';

/// Pick a file, see every row checked, then commit only the valid rows.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  String? _storeId;
  String? _fileName;
  List<List<String>>? _table;
  bool _errorsOnly = false;
  String? _parseError;

  Future<void> _pick(Tr tr) async {
    try {
      final file = await pickTextFile(accept: '.csv,text/csv');
      if (file == null || !mounted) return;
      setState(() {
        _fileName = file.name;
        _parseError = null;
        _table = null;
        try {
          _table = parseCsv(file.text);
        } on CsvFormatException catch (e) {
          _parseError = tr('import_file_bad_quotes', {'row': '${e.row}'});
        }
      });
    } catch (e) {
      debugPrint('Could not read file: $e');
      if (mounted) showMessage(context, tr('import_file_unreadable'));
    }
  }

  void _commit(Tr tr, Store store, ImportPreview preview) {
    final repo = context.read<SessionController>().repositoryFor(store.id);
    final lines = [
      for (final row in preview.validRows)
        CatalogueLine(row.product!, openingStockMilli: row.openingStockMilli),
    ];
    final batches = CatalogueWriter(repo).write(lines, label: 'importProducts');
    showMessage(
      context,
      tr('import_done', {'count': '${lines.length}', 'batches': '$batches'}),
    );
    context.go('/products');
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final scoped = scopedStores(context);
    final selectable = session.stores;
    final selected = selectable.where((s) => s.id == _storeId).firstOrNull ??
        (scoped.length == 1 ? scoped.first : null);

    return PageBody(
      title: tr('import_products'),
      onBack: () => context.go('/products'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('import_instructions')),
                const SizedBox(height: kGap),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('import-store-${selected?.id}'),
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('import_into_store')),
                    items: [
                      for (final s in selectable)
                        DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _storeId = v),
                  ),
                ),
                const SizedBox(height: kGap),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pick(tr),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text(tr('choose_file')),
                    ),
                    if (_fileName != null) Text(_fileName!),
                  ],
                ),
                if (_parseError != null) ...[
                  const SizedBox(height: 8),
                  Text(_parseError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_table != null && selected == null)
            EmptyState(message: tr('import_pick_store'), icon: Icons.storefront_outlined)
          else if (_table != null && selected != null)
            StoreStreamBuilder<List<Product>>(
              stores: [selected],
              cacheKey: 'import-existing',
              source: (repo) => repo.products(includeInactive: true),
              builder: (context, data) => _Preview(
                preview: validateProductCsv(_table!, data[selected.id] ?? const []),
                errorsOnly: _errorsOnly,
                onToggleErrors: (v) => setState(() => _errorsOnly = v),
                onCommit: (preview) => _commit(tr, selected, preview),
              ),
            ),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.preview,
    required this.errorsOnly,
    required this.onToggleErrors,
    required this.onCommit,
  });
  final ImportPreview preview;
  final bool errorsOnly;
  final ValueChanged<bool> onToggleErrors;
  final void Function(ImportPreview preview) onCommit;

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final fileError = preview.fileError;
    if (fileError != null) {
      return Card(
        child: EmptyState(icon: Icons.error_outline, message: tr(fileError.key, fileError.args)),
      );
    }
    final shown = errorsOnly ? preview.rows.where((r) => !r.isValid).toList() : preview.rows;
    String raw(ImportRow r, ProductCsvColumn c) => r.raw[c] ?? '';
    final columns = <TableCol<ImportRow>>[
      TableCol.text(tr('import_row'), (r) => '${r.rowNumber}'),
      TableCol(
        tr('status'),
        (r) => switch (r.action) {
          ImportAction.create =>
            StatusChip(label: tr('import_status_new'), color: KiranaColors.received, icon: Icons.add),
          ImportAction.update => StatusChip(
              label: tr('import_status_update'),
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.sync,
            ),
          ImportAction.invalid =>
            StatusChip(label: tr('import_status_error'), color: KiranaColors.dues, icon: Icons.close),
        },
      ),
      TableCol.text(tr('name'), (r) => raw(r, ProductCsvColumn.name)),
      TableCol.text(tr('product_name_te'), (r) => raw(r, ProductCsvColumn.nameTe)),
      TableCol.text(tr('barcode'), (r) => raw(r, ProductCsvColumn.barcode)),
      TableCol.text(tr('category'), (r) => raw(r, ProductCsvColumn.category)),
      TableCol.text(tr('unit'), (r) => raw(r, ProductCsvColumn.unit)),
      TableCol.text(tr('price'), (r) => raw(r, ProductCsvColumn.price)),
      TableCol.text(tr('cost'), (r) => raw(r, ProductCsvColumn.cost)),
      TableCol.text(tr('stock'), (r) => raw(r, ProductCsvColumn.stock)),
      TableCol.text(tr('low_stock_level'), (r) => raw(r, ProductCsvColumn.lowStock)),
      TableCol(
        tr('import_issues'),
        (r) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final issue in r.errors)
                Text(tr(issue.key, issue.args), style: const TextStyle(color: KiranaColors.dues)),
              for (final issue in r.warnings)
                Text(tr(issue.key, issue.args), style: const TextStyle(color: KiranaColors.warning)),
            ],
          ),
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: tr('import_preview'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TileGrid(
                children: [
                  StatTile(label: tr('import_new_products'), value: '${preview.createCount}'),
                  StatTile(label: tr('import_updates'), value: '${preview.updateCount}'),
                  StatTile(label: tr('import_rows_with_errors'), value: '${preview.invalidCount}'),
                ],
              ),
              const SizedBox(height: kGap),
              Muted(tr('import_update_note')),
              const SizedBox(height: kGap),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton(
                    onPressed: preview.validCount == 0 ? null : () => onCommit(preview),
                    child: Text(tr('import_commit', {'count': '${preview.validCount}'})),
                  ),
                  if (preview.invalidCount > 0)
                    FilterChip(
                      label: Text(tr('import_errors_only')),
                      selected: errorsOnly,
                      onSelected: onToggleErrors,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminTable<ImportRow>(
          columns: columns,
          rows: shown,
          emptyMessage: tr('import_no_rows'),
        ),
      ],
    );
  }
}
