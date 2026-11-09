import 'package:kirana_core/kirana_core.dart';

import 'dates.dart';

/// Rollups for all stores, one summary per day that has any data.
Map<String, PeriodSummary> dailySummaries(Iterable<List<DayRollup>> storesDays) {
  final grouped = <String, List<DayRollup>>{};
  for (final days in storesDays) {
    for (final d in days) {
      grouped.putIfAbsent(d.dayKey, () => []).add(d);
    }
  }
  return grouped.map((k, v) => MapEntry(k, PeriodSummary.of(v)));
}

/// Sales of one product name across the chosen stores.
class NamedProductSales {
  NamedProductSales(this.name);
  final String name;
  int qtyMilli = 0;
  int revenuePaise = 0;
  int cogsPaise = 0;
  int get profitPaise => revenuePaise - cogsPaise;

  /// Margin as a percentage of revenue, or null when nothing was sold.
  double? get marginPercent => revenuePaise == 0 ? null : profitPaise * 100 / revenuePaise;
}

/// Each store keeps its own catalogue ids, so stores are joined on the product
/// name; a product with the same name in two stores becomes one line.
List<NamedProductSales> aggregateProductSales(
  Map<String, List<DayRollup>> daysByStore,
  Map<String, List<Product>> productsByStore,
  String language, {
  int? limit,
  String unknownName = '-',
}) {
  final totals = <String, NamedProductSales>{};
  daysByStore.forEach((storeId, days) {
    final names = {
      for (final p in productsByStore[storeId] ?? const <Product>[]) p.id: p,
    };
    for (final sale in productSales(days)) {
      final product = names[sale.productId];
      final name = product?.displayName(language) ?? unknownName;
      final line = totals.putIfAbsent(
          (product?.name ?? sale.productId).toLowerCase(), () => NamedProductSales(name));
      line
        ..qtyMilli += sale.qtyMilli
        ..revenuePaise += sale.revenuePaise
        ..cogsPaise += sale.cogsPaise;
    }
  });
  final list = totals.values.toList()
    ..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
  return limit == null || list.length <= limit ? list : list.sublist(0, limit);
}

enum AgeBucket { noDueDate, notYetDue, days1to30, days31to60, days61to90, over90 }

/// Whole calendar days past the due date; 0 on the day itself, negative before.
int? daysPastDue(Customer customer, DateTime now) {
  final due = customer.dueDate;
  if (due == null) return null;
  return dateOnly(now).difference(dateOnly(due)).inHours ~/ 24;
}

AgeBucket ageBucket(Customer customer, DateTime now) {
  final days = daysPastDue(customer, now);
  if (days == null) return AgeBucket.noDueDate;
  if (days <= 0) return AgeBucket.notYetDue;
  if (days <= 30) return AgeBucket.days1to30;
  if (days <= 60) return AgeBucket.days31to60;
  if (days <= 90) return AgeBucket.days61to90;
  return AgeBucket.over90;
}

/// Total dues in each ageing bucket, in bucket order.
Map<AgeBucket, int> duesAgeing(Iterable<Customer> customers, DateTime now) {
  final out = {for (final b in AgeBucket.values) b: 0};
  for (final c in customers) {
    if (!c.hasDues || c.archived) continue;
    final bucket = ageBucket(c, now);
    out[bucket] = out[bucket]! + c.balancePaise;
  }
  return out;
}
