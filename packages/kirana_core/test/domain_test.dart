import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';

Product rice({int price = 6050, int cost = 5200, int stock = 10000}) => Product(
      id: 'rice',
      name: 'Rice',
      nameTe: 'బియ్యం',
      unit: Unit.kg,
      pricePaise: price,
      costPaise: cost,
      stockMilli: stock,
    );

void main() {
  group('money', () {
    test('formats with Indian digit grouping', () {
      expect(formatRupees(12345678900), '₹12,34,56,789');
      expect(formatRupees(150), '₹1.50');
      expect(formatRupees(-105), '-₹1.05');
      expect(formatRupees(0), '₹0');
    });

    test('parses rupees exactly without floating point drift', () {
      expect(parseRupees('19.99'), 1999);
      expect(parseRupees('1,250.5'), 125050);
      expect(parseRupees('₹0.07'), 7);
      expect(parseRupees('1.234'), isNull);
      expect(parseRupees('-5'), isNull);
      expect(parseRupees('abc'), isNull);
      expect(parseRupees(''), isNull);
    });

    test('parses and formats quantities', () {
      expect(parseQuantity('1.25'), 1250);
      expect(parseQuantity('0.005'), 5);
      expect(parseQuantity('0'), isNull);
      expect(parseQuantity('1.2345'), isNull);
      expect(formatQuantity(1250), '1.25');
      expect(formatQuantity(2000), '2');
      expect(formatQuantity(-500), '-0.5');
    });

    test('line value rounds half up to the paisa', () {
      expect(lineValue(6050, 250), 1513); // 15.125 rupees
      expect(lineValue(100, 1000), 100);
      expect(lineValue(333, 1500), 500); // 499.5
    });

    test('day key is the local calendar date', () {
      expect(dayKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
    });
  });

  group('cart', () {
    test('merges repeat products and totals with discount', () {
      final cart = Cart()
        ..addProduct(rice(), 1000)
        ..addProduct(rice(), 500)
        ..addCustom('Carry bag', 500);
      cart.discountPaise = 75;
      expect(cart.lines, hasLength(2));
      expect(cart.subtotalPaise, 9075 + 500);
      expect(cart.totalPaise, 9500);
    });

    test('rejects invalid bills', () {
      final cart = Cart();
      expect(cart.validate(const PaymentSplit()), CartError.empty);
      cart.addProduct(rice(), 1000);
      expect(cart.validate(const PaymentSplit(cashPaise: 1)), CartError.paymentMismatch);
      expect(cart.validate(const PaymentSplit(creditPaise: 6050)), CartError.creditNeedsCustomer);
      expect(
        cart.validate(const PaymentSplit(cashPaise: 7000, upiPaise: -950)),
        CartError.negativePayment,
      );
      cart.discountPaise = 7000;
      expect(cart.validate(const PaymentSplit(cashPaise: -950)), CartError.discountTooLarge);
      cart.discountPaise = 0;
      cart.lines.first.qtyMilli = 0;
      expect(cart.validate(const PaymentSplit()), CartError.invalidQuantity);
    });

    test('accepts a split payment', () {
      final cart = Cart()..addProduct(rice(), 1000);
      const split = PaymentSplit(cashPaise: 50, upiPaise: 1000, creditPaise: 5000);
      expect(cart.validate(split, customer: const Customer(id: 'c', name: 'A')), isNull);
    });

    test('flags credit beyond the limit; zero limit means none', () {
      final cart = Cart()..addProduct(rice(), 1000);
      const split = PaymentSplit(creditPaise: 6050);
      const limited = Customer(id: 'c', name: 'A', creditLimitPaise: 10000, balancePaise: 5000);
      const unlimited = Customer(id: 'c', name: 'A', balancePaise: 9999999);
      expect(cart.exceedsCreditLimit(split, limited), isTrue);
      expect(cart.exceedsCreditLimit(split, unlimited), isFalse);
    });
  });

  group('reports', () {
    const dayA = DayRollup(
      dayKey: '2026-11-01',
      salesPaise: 100000,
      cogsPaise: 80000,
      billCount: 4,
      cashSalesPaise: 60000,
      upiSalesPaise: 30000,
      creditSalesPaise: 10000,
      collectionCashPaise: 5000,
      expensePaise: 3000,
      expenseCashPaise: 3000,
      supplierCashPaise: 20000,
      items: {'x': DayItem(qtyMilli: 3000, revenuePaise: 9000, cogsPaise: 6000)},
    );
    const dayB = DayRollup(
      dayKey: '2026-11-02',
      salesPaise: 50000,
      cogsPaise: 35000,
      billCount: 1,
      cashSalesPaise: 50000,
      items: {
        'x': DayItem(qtyMilli: 1000, revenuePaise: 3000, cogsPaise: 2000),
        'y': DayItem(qtyMilli: 1000, revenuePaise: 47000, cogsPaise: 33000),
      },
    );

    test('summarises profit and cash across days', () {
      final s = PeriodSummary.of([dayA, dayB]);
      expect(s.salesPaise, 150000);
      expect(s.grossProfitPaise, 35000);
      expect(s.netProfitPaise, 32000);
      expect(s.billCount, 5);
      expect(s.averageBillPaise, 30000);
      expect(s.netCashPaise, 60000 + 5000 - 3000 - 20000 + 50000);
    });

    test('average bill is zero when there are no bills', () {
      expect(PeriodSummary.of(const []).averageBillPaise, 0);
    });

    test('ranks products by revenue and drops fully voided ones', () {
      const voided = DayRollup(
        dayKey: '2026-11-03',
        items: {'z': DayItem(qtyMilli: 0, revenuePaise: 0, cogsPaise: 0)},
      );
      final list = productSales([dayA, dayB, voided]);
      expect(list.map((p) => p.productId), ['y', 'x']);
      expect(list.last.qtyMilli, 4000);
      expect(list.last.profitPaise, 4000);
      expect(productSales([dayA, dayB], limit: 1), hasLength(1));
    });

    test('orders reminders overdue first, then by amount', () {
      final now = DateTime(2026, 11, 9);
      final list = customersToRemind([
        const Customer(id: 'clear', name: 'A'),
        const Customer(id: 'big', name: 'B', balancePaise: 90000),
        Customer(id: 'late', name: 'C', balancePaise: 100, dueDate: DateTime(2026, 11, 1)),
        const Customer(id: 'gone', name: 'D', balancePaise: 50, archived: true),
      ], now);
      expect(list.map((c) => c.id), ['late', 'big']);
    });

    test('outstanding ignores advances and archived customers', () {
      expect(
        totalOutstanding(const [
          Customer(id: 'a', name: 'A', balancePaise: 500),
          Customer(id: 'b', name: 'B', balancePaise: -300),
          Customer(id: 'c', name: 'C', balancePaise: 900, archived: true),
        ]),
        500,
      );
    });

    test('inventory value skips inactive and negative stock', () {
      expect(
        inventoryValue([
          rice(cost: 5000, stock: 2500),
          const Product(id: 'n', name: 'N', costPaise: 100, stockMilli: -1000),
          const Product(id: 'i', name: 'I', costPaise: 100, stockMilli: 1000, active: false),
        ]),
        12500,
      );
    });
  });

  group('messages', () {
    test('normalises Indian mobile numbers', () {
      expect(normalizeIndianPhone('98765 43210'), '919876543210');
      expect(normalizeIndianPhone('+91-98765-43210'), '919876543210');
      expect(normalizeIndianPhone('09876543210'), '919876543210');
      expect(normalizeIndianPhone('12345'), isNull);
      expect(normalizeIndianPhone('1234567890'), isNull);
    });

    test('whatsapp link encodes Telugu text', () {
      final uri = whatsappUri('9876543210', 'నమస్కారం & hi')!;
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919876543210');
      expect(uri.queryParameters['text'], 'నమస్కారం & hi');
      expect(whatsappUri('123', 'x'), isNull);
    });

    test('reminder message follows language and includes UPI', () {
      const c = Customer(id: 'c', name: 'Ravi', balancePaise: 125000);
      final te = reminderMessage(language: 'te', shopName: 'Sri', customer: c, upiId: 'a@upi');
      final en = reminderMessage(language: 'en', shopName: 'Sri', customer: c);
      expect(te, contains('బాకీ'));
      expect(te, contains('₹1,250'));
      expect(te, contains('a@upi'));
      expect(en, contains('outstanding'));
      expect(en, isNot(contains('UPI')));
    });

    test('text receipt shows the items and only used payment modes', () {
      final bill = Bill(
        id: 'b',
        number: '261109-K7-1',
        items: const [
          BillItem(
            productId: 'rice',
            name: 'Rice',
            nameTe: 'బియ్యం',
            unit: Unit.kg,
            qtyMilli: 1500,
            pricePaise: 6000,
            costPaise: 5000,
            totalPaise: 9000,
          ),
        ],
        subtotalPaise: 9000,
        discountPaise: 0,
        totalPaise: 9000,
        cashPaise: 9000,
        upiPaise: 0,
        creditPaise: 0,
        at: DateTime(2026, 11, 9, 10),
        dayKey: '2026-11-09',
        byUid: 'u',
        byName: 'U',
      );
      const store = Store(id: 's', name: 'Sri Stores', receiptFooter: 'Thanks');
      final te = receiptText(language: 'te', store: store, bill: bill);
      expect(te, contains('బియ్యం 1.5 x ₹60 = ₹90'));
      expect(te, contains('నగదు: ₹90'));
      expect(te, isNot(contains('UPI')));
      expect(te, endsWith('Thanks'));
      expect(receiptText(language: 'en', store: store, bill: bill), contains('Rice 1.5'));
    });
  });

  test('shared strings have the same keys and placeholders in both languages', () {
    expect(commonTe.keys.toSet(), commonEn.keys.toSet());
    final slot = RegExp(r'\{\w+\}');
    for (final key in commonEn.keys) {
      Set<String> slots(String s) => slot.allMatches(s).map((m) => m[0]!).toSet();
      expect(slots(commonTe[key]!), slots(commonEn[key]!), reason: key);
    }
  });
}
