import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/utils/csv.dart';

void main() {
  group('parseCsv', () {
    test('plain rows with CRLF and LF', () {
      expect(parseCsv('a,b\r\nc,d\ne,f'), [
        ['a', 'b'],
        ['c', 'd'],
        ['e', 'f'],
      ]);
    });

    test('quoted fields with embedded commas, quotes and newlines', () {
      expect(parseCsv('"Rice, Sona Masoori","5"" bag","line1\nline2"\n'), [
        ['Rice, Sona Masoori', '5" bag', 'line1\nline2'],
      ]);
    });

    test('strips a byte-order mark and keeps Telugu', () {
      expect(parseCsv('﻿పేరు,ధర\nకందిపప్పు,120\n'), [
        ['పేరు', 'ధర'],
        ['కందిపప్పు', '120'],
      ]);
    });

    test('keeps empty fields, including a trailing one', () {
      expect(parseCsv('a,,c\nd,e,'), [
        ['a', '', 'c'],
        ['d', 'e', ''],
      ]);
    });

    test('a blank line in the middle stays so row numbers match the file', () {
      final rows = parseCsv('a\n\nb\n');
      expect(rows.length, 3);
      expect(rows[1], ['']);
    });

    test('a final newline does not add a row', () {
      expect(parseCsv('a,b\n').length, 1);
    });

    test('a quote in the middle of a field is literal', () {
      expect(parseCsv('5" pipe,x'), [
        ['5" pipe', 'x'],
      ]);
    });

    test('an unterminated quote is reported with its row', () {
      expect(
        () => parseCsv('a,b\n"open,c\nd'),
        throwsA(isA<CsvFormatException>().having((e) => e.row, 'row', 2)),
      );
    });

    test('empty input has no rows', () {
      expect(parseCsv(''), isEmpty);
    });
  });

  group('buildCsv', () {
    test('adds a UTF-8 BOM and CRLF line endings', () {
      expect(
        buildCsv([
          ['a', 'b'],
        ]),
        '﻿a,b\r\n',
      );
    });

    test('quotes only what needs quoting', () {
      expect(
        buildCsv([
          ['a,b', 'say "hi"', 'x\ny', 'plain', null, 5],
        ], bom: false),
        '"a,b","say ""hi""","x\ny",plain,,5\r\n',
      );
    });

    test('neutralises spreadsheet formulas in text, not numbers', () {
      expect(csvEscape('=SUM(A1:A2)'), "'=SUM(A1:A2)");
      expect(csvEscape('@cmd'), "'@cmd");
      expect(csvEscape('-1250.50'), '-1250.50');
      expect(csvEscape(-5), '-5');
    });

    test('round trips through parseCsv', () {
      final rows = [
        ['Name', 'Note'],
        ['కందిపప్పు, 1 కిలో', 'He said "ok"\nthen left'],
      ];
      expect(parseCsv(buildCsv(rows)), rows);
    });

    test('csvMoney gives a plain number without grouping', () {
      expect(csvMoney(12345050), '123450.50');
      expect(csvMoney(-500), '-5');
    });
  });
}
