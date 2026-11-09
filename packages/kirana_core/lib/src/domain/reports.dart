import 'models.dart';

class ProductSales {
  const ProductSales({
    required this.productId,
    required this.qtyMilli,
    required this.revenuePaise,
    required this.cogsPaise,
  });
  final String productId;
  final int qtyMilli;
  final int revenuePaise;
  final int cogsPaise;
  int get profitPaise => revenuePaise - cogsPaise;
}

/// Totals across a run of daily rollups, for one or many stores.
class PeriodSummary {
  const PeriodSummary({
    required this.salesPaise,
    required this.discountPaise,
    required this.billCount,
    required this.cogsPaise,
    required this.cashSalesPaise,
    required this.upiSalesPaise,
    required this.creditSalesPaise,
    required this.collectionCashPaise,
    required this.collectionUpiPaise,
    required this.expensePaise,
    required this.purchasePaise,
    required this.netCashPaise,
    required this.netUpiPaise,
  });

  factory PeriodSummary.of(Iterable<DayRollup> days) {
    var sales = 0, discount = 0, bills = 0, cogs = 0, cash = 0, upi = 0;
    var credit = 0, inCash = 0, inUpi = 0, expense = 0, purchase = 0;
    var netCash = 0, netUpi = 0;
    for (final d in days) {
      sales += d.salesPaise;
      discount += d.discountPaise;
      bills += d.billCount;
      cogs += d.cogsPaise;
      cash += d.cashSalesPaise;
      upi += d.upiSalesPaise;
      credit += d.creditSalesPaise;
      inCash += d.collectionCashPaise;
      inUpi += d.collectionUpiPaise;
      expense += d.expensePaise;
      purchase += d.purchasePaise;
      netCash += d.netCashPaise;
      netUpi += d.netUpiPaise;
    }
    return PeriodSummary(
      salesPaise: sales,
      discountPaise: discount,
      billCount: bills,
      cogsPaise: cogs,
      cashSalesPaise: cash,
      upiSalesPaise: upi,
      creditSalesPaise: credit,
      collectionCashPaise: inCash,
      collectionUpiPaise: inUpi,
      expensePaise: expense,
      purchasePaise: purchase,
      netCashPaise: netCash,
      netUpiPaise: netUpi,
    );
  }

  final int salesPaise;
  final int discountPaise;
  final int billCount;
  final int cogsPaise;
  final int cashSalesPaise;
  final int upiSalesPaise;
  final int creditSalesPaise;
  final int collectionCashPaise;
  final int collectionUpiPaise;
  final int expensePaise;
  final int purchasePaise;
  final int netCashPaise;
  final int netUpiPaise;

  int get grossProfitPaise => salesPaise - cogsPaise;
  int get netProfitPaise => grossProfitPaise - expensePaise;
  int get averageBillPaise => billCount == 0 ? 0 : salesPaise ~/ billCount;
}

/// Products sold across [days], best revenue first.
List<ProductSales> productSales(Iterable<DayRollup> days, {int? limit}) {
  final totals = <String, List<int>>{};
  for (final d in days) {
    d.items.forEach((id, item) {
      final t = totals.putIfAbsent(id, () => [0, 0, 0]);
      t[0] += item.qtyMilli;
      t[1] += item.revenuePaise;
      t[2] += item.cogsPaise;
    });
  }
  final list = totals.entries
      .where((e) => e.value[0] > 0)
      .map((e) => ProductSales(
            productId: e.key,
            qtyMilli: e.value[0],
            revenuePaise: e.value[1],
            cogsPaise: e.value[2],
          ))
      .toList()
    ..sort((a, b) => b.revenuePaise.compareTo(a.revenuePaise));
  return limit == null || list.length <= limit ? list : list.sublist(0, limit);
}

/// Customers with dues, most overdue first and then largest balance.
List<Customer> customersToRemind(Iterable<Customer> customers, DateTime now) {
  final list = customers.where((c) => c.hasDues && !c.archived).toList();
  int rank(Customer c) => c.isOverdue(now) ? 0 : 1;
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : b.balancePaise.compareTo(a.balancePaise);
  });
  return list;
}

int totalOutstanding(Iterable<Customer> customers) => customers
    .where((c) => !c.archived && c.balancePaise > 0)
    .fold(0, (sum, c) => sum + c.balancePaise);

/// Stock value at cost price.
int inventoryValue(Iterable<Product> products) => products
    .where((p) => p.active && p.stockMilli > 0)
    .fold(0, (sum, p) => sum + (p.costPaise * p.stockMilli + 500) ~/ 1000);
