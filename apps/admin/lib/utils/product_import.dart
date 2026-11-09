import 'package:kirana_core/kirana_core.dart';

import '../strings.dart';
import 'csv.dart';

/// A message about one row: a translation key and its arguments.
class ImportIssue {
  const ImportIssue(this.key, [this.args = const {}]);
  final String key;
  final Map<String, String> args;
}

/// Every issue key the validator can produce, so a test can check translations.
const List<String> importIssueKeys = [
  'import_err_name_required',
  'import_err_price_required',
  'import_err_price_invalid',
  'import_err_cost_invalid',
  'import_err_unit_invalid',
  'import_err_stock_invalid',
  'import_err_low_invalid',
  'import_err_barcode_scientific',
  'import_err_duplicate_barcode',
  'import_err_duplicate_name',
  'import_err_same_product',
  'import_err_too_long',
  'import_warn_cost_above_price',
  'import_warn_cost_missing',
  'import_warn_stock_ignored',
  'import_file_no_header',
  'import_file_missing_columns',
  'import_file_empty',
];

enum ImportAction { create, update, invalid }

class ImportRow {
  ImportRow({required this.rowNumber, required this.raw});

  /// 1-based row in the file, counting the header.
  final int rowNumber;
  final Map<ProductCsvColumn, String> raw;
  final List<ImportIssue> errors = [];
  final List<ImportIssue> warnings = [];
  Product? product;
  int openingStockMilli = 0;
  ImportAction action = ImportAction.invalid;

  bool get isValid => errors.isEmpty && action != ImportAction.invalid;
}

class ImportPreview {
  ImportPreview({this.fileError, this.rows = const []});
  final ImportIssue? fileError;
  final List<ImportRow> rows;

  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;
  int get createCount =>
      rows.where((r) => r.isValid && r.action == ImportAction.create).length;
  int get updateCount =>
      rows.where((r) => r.isValid && r.action == ImportAction.update).length;
  List<ImportRow> get validRows => rows.where((r) => r.isValid).toList();
}

enum ProductCsvColumn { name, nameTe, barcode, category, unit, price, cost, stock, lowStock }

/// Translation key for each column's header in export and template files.
const Map<ProductCsvColumn, String> productCsvHeaderKeys = {
  ProductCsvColumn.name: 'csv_col_name',
  ProductCsvColumn.nameTe: 'csv_col_name_te',
  ProductCsvColumn.barcode: 'csv_col_barcode',
  ProductCsvColumn.category: 'csv_col_category',
  ProductCsvColumn.unit: 'csv_col_unit',
  ProductCsvColumn.price: 'csv_col_price',
  ProductCsvColumn.cost: 'csv_col_cost',
  ProductCsvColumn.stock: 'csv_col_stock',
  ProductCsvColumn.lowStock: 'csv_col_low_stock',
};

const Map<ProductCsvColumn, List<String>> _headerAliases = {
  ProductCsvColumn.name: ['name', 'productname', 'product', 'item', 'itemname'],
  ProductCsvColumn.nameTe: ['telugu', 'teluguname', 'nameintelugu', 'namete'],
  ProductCsvColumn.barcode: ['barcode', 'code', 'ean'],
  ProductCsvColumn.category: ['category', 'group'],
  ProductCsvColumn.unit: ['unit', 'uom'],
  ProductCsvColumn.price: ['price', 'sellingprice', 'saleprice', 'mrp'],
  ProductCsvColumn.cost: ['cost', 'costprice', 'purchaseprice'],
  ProductCsvColumn.stock: ['stock', 'openingstock', 'qty', 'quantity'],
  ProductCsvColumn.lowStock: ['lowstock', 'lowstocklevel', 'reorderlevel', 'minstock'],
};

const Map<String, Unit> _unitAliases = {
  '': Unit.piece,
  'piece': Unit.piece,
  'pieces': Unit.piece,
  'pc': Unit.piece,
  'pcs': Unit.piece,
  'nos': Unit.piece,
  'no': Unit.piece,
  'ముక్క': Unit.piece,
  'kg': Unit.kg,
  'kgs': Unit.kg,
  'kilo': Unit.kg,
  'kilogram': Unit.kg,
  'కిలో': Unit.kg,
  'litre': Unit.litre,
  'liter': Unit.litre,
  'litres': Unit.litre,
  'liters': Unit.litre,
  'l': Unit.litre,
  'lt': Unit.litre,
  'ltr': Unit.litre,
  'లీటర్': Unit.litre,
  'packet': Unit.packet,
  'packets': Unit.packet,
  'pack': Unit.packet,
  'pkt': Unit.packet,
  'ప్యాకెట్': Unit.packet,
};

String _norm(String header) =>
    header.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-.]+'), '');

Map<String, ProductCsvColumn> _headerLookup() {
  final lookup = <String, ProductCsvColumn>{};
  _headerAliases.forEach((column, aliases) {
    for (final alias in aliases) {
      lookup[alias] = column;
    }
  });
  productCsvHeaderKeys.forEach((column, key) {
    lookup[_norm(adminEn[key]!)] = column;
    lookup[_norm(adminTe[key]!)] = column;
  });
  return lookup;
}

/// Stock and low-stock level: a blank or zero is allowed, unlike parseQuantity.
int? _parseStock(String text) {
  final t = text.trim().replaceAll(',', '');
  if (t.isEmpty || RegExp(r'^0+(\.0{1,3})?$').hasMatch(t)) return 0;
  return parseQuantity(t);
}

const int _maxTextLength = 120;

/// Checks a parsed CSV against the store's existing products (active or not).
/// Nothing is written here. A row matching an existing product by barcode, or
/// failing that by name, updates that product and leaves its stock alone, so
/// importing the same file twice cannot duplicate products or double the stock.
ImportPreview validateProductCsv(List<List<String>> table, List<Product> existing) {
  if (table.isEmpty || table.every((r) => r.join().trim().isEmpty)) {
    return ImportPreview(fileError: const ImportIssue('import_file_empty'));
  }
  final lookup = _headerLookup();
  final header = table.first;
  final columns = <ProductCsvColumn, int>{};
  for (var i = 0; i < header.length; i++) {
    final column = lookup[_norm(header[i])];
    if (column != null) columns.putIfAbsent(column, () => i);
  }
  if (columns.isEmpty) {
    return ImportPreview(fileError: const ImportIssue('import_file_no_header'));
  }
  final missing = [
    for (final c in const [ProductCsvColumn.name, ProductCsvColumn.price])
      if (!columns.containsKey(c)) adminEn[productCsvHeaderKeys[c]]!,
  ];
  if (missing.isNotEmpty) {
    return ImportPreview(
      fileError: ImportIssue('import_file_missing_columns', {'columns': missing.join(', ')}),
    );
  }

  final byBarcode = <String, Product>{
    for (final p in existing)
      if (p.barcode.isNotEmpty) p.barcode: p,
  };
  final byName = <String, Product>{for (final p in existing) p.name.trim().toLowerCase(): p};
  final seenBarcodes = <String, int>{};
  final seenNames = <String, int>{};
  final seenExisting = <String, int>{};
  final rows = <ImportRow>[];

  for (var i = 1; i < table.length; i++) {
    final cells = table[i];
    if (cells.join().trim().isEmpty) continue;
    String cell(ProductCsvColumn c) {
      final index = columns[c];
      return index != null && index < cells.length ? cells[index].trim() : '';
    }

    final row = ImportRow(
      rowNumber: i + 1,
      raw: {for (final c in ProductCsvColumn.values) c: cell(c)},
    );
    rows.add(row);

    final name = cell(ProductCsvColumn.name);
    final nameTe = cell(ProductCsvColumn.nameTe);
    final barcode = cell(ProductCsvColumn.barcode);
    final category = cell(ProductCsvColumn.category);

    if (name.isEmpty) row.errors.add(const ImportIssue('import_err_name_required'));
    if (name.length > _maxTextLength || nameTe.length > _maxTextLength) {
      row.errors.add(const ImportIssue('import_err_too_long'));
    }
    if (RegExp(r'^\d+(\.\d+)?[eE]\+?\d+$').hasMatch(barcode)) {
      row.errors.add(const ImportIssue('import_err_barcode_scientific'));
    }

    final priceText = cell(ProductCsvColumn.price);
    final price = priceText.isEmpty ? null : parseRupees(priceText);
    if (priceText.isEmpty) {
      row.errors.add(const ImportIssue('import_err_price_required'));
    } else if (price == null) {
      row.errors.add(ImportIssue('import_err_price_invalid', {'value': priceText}));
    }

    final costText = cell(ProductCsvColumn.cost);
    final cost = costText.isEmpty ? 0 : parseRupees(costText);
    if (cost == null) {
      row.errors.add(ImportIssue('import_err_cost_invalid', {'value': costText}));
    } else if (costText.isEmpty) {
      row.warnings.add(const ImportIssue('import_warn_cost_missing'));
    } else if (price != null && cost > price) {
      row.warnings.add(const ImportIssue('import_warn_cost_above_price'));
    }

    final unitText = cell(ProductCsvColumn.unit).toLowerCase();
    final unit = _unitAliases[unitText];
    if (unit == null) {
      row.errors.add(ImportIssue('import_err_unit_invalid', {'value': unitText}));
    }

    final stockText = cell(ProductCsvColumn.stock);
    final stock = _parseStock(stockText);
    if (stock == null) {
      row.errors.add(ImportIssue('import_err_stock_invalid', {'value': stockText}));
    }
    final lowText = cell(ProductCsvColumn.lowStock);
    final low = _parseStock(lowText);
    if (low == null) {
      row.errors.add(ImportIssue('import_err_low_invalid', {'value': lowText}));
    }

    final nameKey = name.toLowerCase();
    if (barcode.isNotEmpty) {
      final first = seenBarcodes[barcode];
      if (first != null) {
        row.errors.add(ImportIssue('import_err_duplicate_barcode', {'row': '$first'}));
      } else {
        seenBarcodes[barcode] = row.rowNumber;
      }
    }
    if (name.isNotEmpty) {
      final first = seenNames[nameKey];
      if (first != null) {
        row.errors.add(ImportIssue('import_err_duplicate_name', {'row': '$first'}));
      } else {
        seenNames[nameKey] = row.rowNumber;
      }
    }

    final match = (barcode.isNotEmpty ? byBarcode[barcode] : null) ?? byName[nameKey];
    if (match != null) {
      final first = seenExisting[match.id];
      if (first != null) {
        row.errors.add(ImportIssue('import_err_same_product', {'row': '$first'}));
      } else {
        seenExisting[match.id] = row.rowNumber;
      }
      if (stock != null && stock != 0) {
        row.warnings.add(const ImportIssue('import_warn_stock_ignored'));
      }
    }

    if (row.errors.isNotEmpty) continue;
    row.action = match == null ? ImportAction.create : ImportAction.update;
    row.openingStockMilli = match == null ? stock! : 0;
    row.product = Product(
      id: match?.id ?? '',
      name: name,
      nameTe: nameTe,
      barcode: barcode,
      category: category,
      unit: unit!,
      pricePaise: price!,
      costPaise: cost!,
      lowStockMilli: low!,
      active: match?.active ?? true,
    );
  }
  return ImportPreview(rows: rows);
}

/// One row per product, in the same layout the importer reads back. Stock is
/// included so the file is a useful stock list as well as a template.
List<List<Object?>> productCsvRows(
  List<Product> products,
  String Function(String key) header,
) {
  return [
    [for (final c in ProductCsvColumn.values) header(productCsvHeaderKeys[c]!)],
    for (final p in products)
      [
        p.name,
        p.nameTe,
        p.barcode,
        p.category,
        p.unit.name,
        csvMoney(p.pricePaise),
        csvMoney(p.costPaise),
        formatQuantity(p.stockMilli),
        formatQuantity(p.lowStockMilli),
      ],
  ];
}
