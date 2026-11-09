import 'package:intl/intl.dart';

/// All money is stored as integer paise and all quantities as integer
/// milli-units (1 kg = 1000, 1 piece = 1000). Doubles never touch a balance.
String formatRupees(int paise, {bool symbol = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final digits = NumberFormat.decimalPattern('en_IN').format(whole);
  final cents = fraction == 0 ? '' : '.${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$digits$cents';
}

/// Parses user input like "1,250.50" to paise using exact decimal handling.
/// Returns null for anything that is not a non-negative amount with at most
/// two decimal places.
int? parseRupees(String input) {
  final text = input.trim().replaceAll(',', '').replaceAll('₹', '');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

/// Parses a quantity such as "1.25" into milli-units. Rejects zero.
int? parseQuantity(String input) {
  final match = RegExp(r'^(\d+)(?:\.(\d{1,3}))?$').firstMatch(input.trim());
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(3, '0');
  final milli = whole * 1000 + int.parse(fraction);
  return milli == 0 ? null : milli;
}

/// "1.25", "2", "0.5" — trailing zeros removed.
String formatQuantity(int milli) {
  final negative = milli < 0;
  final abs = milli.abs();
  final whole = abs ~/ 1000;
  final fraction = (abs % 1000).toString().padLeft(3, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${trimmed.isEmpty ? '' : '.$trimmed'}';
}

/// Value of [qtyMilli] units at [paisePerUnit], rounded to the nearest paisa.
int lineValue(int paisePerUnit, int qtyMilli) {
  final product = paisePerUnit * qtyMilli;
  return product >= 0
      ? (product + 500) ~/ 1000
      : -((-product + 500) ~/ 1000);
}

/// Local calendar day, used as the id of the daily rollup document.
String dayKey(DateTime time) {
  final t = time.toLocal();
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-$m-$d';
}
