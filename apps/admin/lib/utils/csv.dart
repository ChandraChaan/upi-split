import 'package:kirana_core/kirana_core.dart';

/// Excel only reads a CSV as UTF-8, and so shows Telugu, when this comes first.
const String utf8Bom = '﻿';

class CsvFormatException implements Exception {
  const CsvFormatException(this.row);

  /// 1-based row where the unterminated quoted field began.
  final int row;
  @override
  String toString() => 'CsvFormatException(row $row)';
}

/// Parses RFC 4180 CSV: quoted fields, doubled quotes, embedded commas and
/// newlines, LF or CRLF, and a leading byte-order mark. Blank lines stay in the
/// result as a row holding one empty field, so row numbers match the file.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith(utf8Bom) ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var quoteStartRow = 0;
  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.write(ch);
      }
      i++;
      continue;
    }
    if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      quoteStartRow = rows.length + 1;
    } else if (ch == ',') {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
    i++;
  }
  if (inQuotes) throw CsvFormatException(quoteStartRow);
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

bool _isFormula(String text) {
  if (text.isEmpty || !'=+-@\t\r'.contains(text[0])) return false;
  return !RegExp(r'^[+-]?\d+(\.\d+)?$').hasMatch(text);
}

/// Quotes one value for a CSV file. Text that a spreadsheet would run as a
/// formula gets a leading apostrophe, because names come from staff input.
String csvEscape(Object? value) {
  var text = value?.toString() ?? '';
  if (value is String && _isFormula(text)) text = "'$text";
  if (text.contains(RegExp(r'[",\r\n]'))) return '"${text.replaceAll('"', '""')}"';
  return text;
}

String buildCsv(Iterable<Iterable<Object?>> rows, {bool bom = true}) {
  final buffer = StringBuffer(bom ? utf8Bom : '');
  for (final row in rows) {
    buffer
      ..write(row.map(csvEscape).join(','))
      ..write('\r\n');
  }
  return buffer.toString();
}

/// A plain number that a spreadsheet can add up, such as 125000.50.
String csvMoney(int paise) => formatRupees(paise, symbol: false).replaceAll(',', '');
