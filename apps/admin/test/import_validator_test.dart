import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/data/catalogue_writer.dart';
import 'package:kirana_admin/utils/csv.dart';
import 'package:kirana_admin/utils/product_import.dart';
import 'package:kirana_core/kirana_core.dart';

const header = 'name,Telugu name,barcode,category,unit,price,cost,stock,low-stock level';

ImportPreview check(String body, {List<Product> existing = const []}) =>
    validateProductCsv(parseCsv('$header\n$body'), existing);

List<String> errorKeys(ImportRow row) => row.errors.map((e) => e.key).toList();

void main() {
  test('a good row becomes a new product in integer paise and milli-units', () {
    final preview = check('Toor Dal,కందిపప్పు,890123,Pulses,kg,120.50,100,12.5,2');
    expect(preview.fileError, isNull);
    expect(preview.createCount, 1);
    final row = preview.rows.single;
    expect(row.isValid, isTrue);
    expect(row.rowNumber, 2);
    expect(row.openingStockMilli, 12500);
    final p = row.product!;
    expect(p.id, '');
    expect(p.name, 'Toor Dal');
    expect(p.nameTe, 'కందిపప్పు');
    expect(p.unit, Unit.kg);
    expect(p.pricePaise, 12050);
    expect(p.costPaise, 10000);
    expect(p.lowStockMilli, 2000);
  });

  test('headers are matched in any order, case and spelling', () {
    final preview = validateProductCsv(
      parseCsv('SELLING PRICE,Product Name\n10,Soap\n'),
      const [],
    );
    expect(preview.validCount, 1);
    expect(preview.rows.single.product!.name, 'Soap');
    expect(preview.rows.single.product!.pricePaise, 1000);
  });

  test('Telugu headers from a Telugu export are understood', () {
    final preview = validateProductCsv(parseCsv('పేరు,అమ్మకం ధర\nసబ్బు,10\n'), const []);
    expect(preview.validCount, 1);
  });

  test('missing required columns is a file-level error', () {
    final preview = validateProductCsv(parseCsv('name,cost\nSoap,5\n'), const []);
    expect(preview.fileError?.key, 'import_file_missing_columns');
    expect(preview.fileError?.args['columns'], contains('Price'));
    expect(preview.rows, isEmpty);
  });

  test('a file with unknown headers is rejected', () {
    expect(
      validateProductCsv(parseCsv('foo,bar\n1,2\n'), const []).fileError?.key,
      'import_file_no_header',
    );
  });

  test('an empty file is rejected', () {
    expect(validateProductCsv(const [], const []).fileError?.key, 'import_file_empty');
  });

  test('each bad field gets its own error and the row is not committed', () {
    final preview = check(',,,,box,abc,xyz,-1,1.2345');
    final row = preview.rows.single;
    expect(row.isValid, isFalse);
    expect(row.action, ImportAction.invalid);
    expect(
      errorKeys(row),
      containsAll(<String>[
        'import_err_name_required',
        'import_err_price_invalid',
        'import_err_cost_invalid',
        'import_err_unit_invalid',
        'import_err_stock_invalid',
        'import_err_low_invalid',
      ]),
    );
    expect(preview.validRows, isEmpty);
  });

  test('blank price is required; blank cost, stock and unit have defaults', () {
    expect(errorKeys(check('Soap,,,,,,,,').rows.single), ['import_err_price_required']);
    final row = check('Soap,,,,,10,,,').rows.single;
    expect(row.isValid, isTrue);
    expect(row.product!.unit, Unit.piece);
    expect(row.product!.costPaise, 0);
    expect(row.openingStockMilli, 0);
    expect(row.warnings.map((w) => w.key), contains('import_warn_cost_missing'));
  });

  test('zero stock is accepted, unlike parseQuantity', () {
    expect(check('Soap,,,,,10,5,0,0').rows.single.isValid, isTrue);
  });

  test('unit synonyms are accepted', () {
    expect(check('A,,,,KGS,10,5,1,').rows.single.product!.unit, Unit.kg);
    expect(check('A,,,,ltr,10,5,1,').rows.single.product!.unit, Unit.litre);
    expect(check('A,,,,pkt,10,5,1,').rows.single.product!.unit, Unit.packet);
    expect(check('A,,,,కిలో,10,5,1,').rows.single.product!.unit, Unit.kg);
  });

  test('cost above price is a warning, not an error', () {
    final row = check('Soap,,,,,10,12,1,').rows.single;
    expect(row.isValid, isTrue);
    expect(row.warnings.map((w) => w.key), contains('import_warn_cost_above_price'));
  });

  test('a barcode mangled by Excel is caught', () {
    expect(
      errorKeys(check('Soap,,8.9E+12,,,10,5,1,').rows.single),
      contains('import_err_barcode_scientific'),
    );
  });

  test('duplicates inside the file are flagged against the first row', () {
    final preview = check('Soap,,111,,,10,5,1,\nSOAP,,222,,,10,5,1,\nOil,,111,,,10,5,1,');
    expect(preview.rows[0].isValid, isTrue);
    expect(errorKeys(preview.rows[1]), ['import_err_duplicate_name']);
    expect(preview.rows[1].errors.single.args['row'], '2');
    expect(errorKeys(preview.rows[2]), ['import_err_duplicate_barcode']);
    expect(preview.validCount, 1);
  });

  test('blank lines are skipped and row numbers still match the file', () {
    final preview = check('Soap,,,,,10,5,1,\n\nOil,,,,,10,5,1,');
    expect(preview.rows.length, 2);
    expect(preview.rows[1].rowNumber, 4);
  });

  group('existing products', () {
    const existing = [
      Product(id: 'x1', name: 'Soap', barcode: '111', stockMilli: 7000, active: false),
    ];

    test('a barcode match updates and leaves stock alone', () {
      final row = check('New Soap,,111,,,20,15,50,', existing: existing).rows.single;
      expect(row.action, ImportAction.update);
      expect(row.product!.id, 'x1');
      expect(row.openingStockMilli, 0);
      expect(row.warnings.map((w) => w.key), contains('import_warn_stock_ignored'));
    });

    test('a name match updates, keeping the active flag', () {
      final row = check('soap,,,,,20,15,,', existing: existing).rows.single;
      expect(row.action, ImportAction.update);
      expect(row.product!.active, isFalse);
    });

    test('two rows cannot update the same product', () {
      final preview = check('Soap,,,,,20,15,,\nOther,,111,,,20,15,,', existing: existing);
      expect(errorKeys(preview.rows[1]), ['import_err_same_product']);
    });

    test('re-validating the same file after import adds nothing new', () {
      final first = check('Soap,,111,,,20,15,5,', existing: const []);
      final created = first.rows.single.product!;
      final existingNow = [
        Product(id: 'new', name: created.name, barcode: created.barcode),
      ];
      final second = check('Soap,,111,,,20,15,5,', existing: existingNow);
      expect(second.createCount, 0);
      expect(second.updateCount, 1);
    });
  });

  group('splitByWrites', () {
    test('never exceeds the limit', () {
      final lines = List.generate(
        1000,
        (i) => CatalogueLine(Product(id: '', name: 'P$i'), openingStockMilli: i.isEven ? 1000 : 0),
      );
      final chunks = splitByWrites(lines, (CatalogueLine l) => l.writeCost);
      for (final chunk in chunks) {
        final cost = chunk.fold<int>(0, (t, l) => t + l.writeCost);
        expect(cost, lessThanOrEqualTo(maxWritesPerBatch));
        expect(maxWritesPerBatch, lessThan(500));
      }
      expect(chunks.expand((c) => c).length, 1000);
      expect(chunks.length, greaterThan(1));
    });

    test('keeps order and handles an empty input', () {
      expect(splitByWrites(<int>[], (int v) => v), isEmpty);
      expect(splitByWrites([1, 2, 3, 4], (int v) => 1, maxWrites: 2), [
        [1, 2],
        [3, 4],
      ]);
    });
  });

  test('productsToCopy skips what the target already has and inactive items', () {
    const source = [
      Product(id: '1', name: 'Soap', barcode: '111', stockMilli: 9000),
      Product(id: '2', name: 'Oil', barcode: '222'),
      Product(id: '3', name: 'Salt'),
      Product(id: '4', name: 'Old', active: false),
    ];
    const target = [
      Product(id: 'a', name: 'Different', barcode: '111'),
      Product(id: 'b', name: 'OIL'),
    ];
    final copies = productsToCopy(source, target);
    expect(copies.map((p) => p.name), ['Salt']);
    expect(copies.single.id, '');
    expect(copies.single.stockMilli, 0);
  });
}
