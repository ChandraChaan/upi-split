import 'package:intl/intl.dart';
import 'package:kirana_core/kirana_core.dart';

String formatDate(DateTime date) => DateFormat('dd/MM/yyyy').format(date.toLocal());
String formatDateTime(DateTime date) =>
    DateFormat('dd/MM/yyyy hh:mm a').format(date.toLocal());

/// Turns a rollup id such as 2026-11-09 into 09/11/2026.
String formatDayKey(String key) {
  final parts = key.split('-');
  return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : key;
}

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// An inclusive range of calendar days.
class DateRange {
  DateRange(DateTime start, DateTime end)
      : start = dateOnly(start),
        end = dateOnly(end);
  final DateTime start;
  final DateTime end;

  DateTime get from => start;

  /// The first instant after the range, for queries with an exclusive end.
  DateTime get toExclusive => DateTime(end.year, end.month, end.day + 1);
  String get fromKey => dayKey(start);
  String get toKey => dayKey(end);
  String get cacheKey => '$fromKey..$toKey';
  bool containsKey(String key) => key.compareTo(fromKey) >= 0 && key.compareTo(toKey) <= 0;

  /// Every day key in the range, oldest first.
  List<String> get dayKeys {
    final out = <String>[];
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(dayKey(d));
    }
    return out;
  }
}

enum RangePreset { today, yesterday, thisWeek, last7, thisMonth, lastMonth, last30, custom }

DateRange presetRange(RangePreset preset, DateTime now, {DateRange? custom}) {
  final d = dateOnly(now);
  DateTime ago(int days) => DateTime(d.year, d.month, d.day - days);
  return switch (preset) {
    RangePreset.today => DateRange(d, d),
    RangePreset.yesterday => DateRange(ago(1), ago(1)),
    RangePreset.thisWeek => DateRange(ago(d.weekday - DateTime.monday), d),
    RangePreset.last7 => DateRange(ago(6), d),
    RangePreset.thisMonth => DateRange(DateTime(d.year, d.month), d),
    RangePreset.lastMonth =>
      DateRange(DateTime(d.year, d.month - 1), DateTime(d.year, d.month, 0)),
    RangePreset.last30 => DateRange(ago(29), d),
    RangePreset.custom => custom ?? DateRange(d, d),
  };
}
