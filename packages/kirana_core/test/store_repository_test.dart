import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';

const owner = Actor(uid: 'u1', name: 'Owner', role: MemberRole.owner);
const cashier = Actor(uid: 'u2', name: 'Cashier', role: MemberRole.cashier);
const storePath = 'businesses/b/stores/s';
final now = DateTime(2026, 11, 9, 11, 30);
const today = '2026-11-09';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeFirebaseFirestore db;
  late StoreRepository repo;
  late Product rice;
  late Customer ravi;

  StoreRepository repoFor(Actor actor, {DateTime? at}) => StoreRepository(
        db,
        businessId: 'b',
        storeId: 's',
        actor: actor,
        clock: () => at ?? now,
      );

  Future<Map<String, dynamic>> doc(String path) async =>
      (await db.doc('$storePath/$path').get()).data() ?? {};

  Future<List<Map<String, dynamic>>> all(String name) async =>
      (await db.collection('$storePath/$name').get()).docs.map((d) => d.data()).toList();

  Future<int> stock() async => (await doc('products/${rice.id}'))['stockMilli'] as int;
  Future<int> balance() async => (await doc('customers/${ravi.id}'))['balancePaise'] as int;

  Cart cartOf(int qtyMilli) => Cart()..addProduct(rice, qtyMilli);

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = repoFor(owner);
    final productId = repo.saveProduct(
      const Product(id: '', name: 'Rice', unit: Unit.kg, pricePaise: 6000, costPaise: 5000),
      openingStockMilli: 10000,
    );
    final customerId = repo.saveCustomer(name: ' Ravi ', phone: '9876543210');
    await flush();
    rice = const Product(id: '', name: 'Rice', unit: Unit.kg, pricePaise: 6000, costPaise: 5000)
        .copyForTest(productId);
    ravi = Customer(id: customerId, name: 'Ravi');
  });

  test('opening stock is recorded as a movement', () async {
    expect(await stock(), 10000);
    final moves = await all('stockMoves');
    expect(moves.single['deltaMilli'], 10000);
    expect((await doc('customers/${ravi.id}'))['name'], 'Ravi');
  });

  test('a cash bill reduces stock and updates the daily totals', () async {
    final bill = repo.createBill(
      cart: cartOf(1500),
      payment: const PaymentSplit(cashPaise: 9000),
      number: 'N1',
    );
    await flush();

    expect(bill.totalPaise, 9000);
    expect(await stock(), 8500);
    final stored = await doc('bills/${bill.id}');
    expect(stored['number'], 'N1');
    expect((stored['items'] as List).single['costPaise'], 5000);
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.salesPaise, 9000);
    expect(day.cashSalesPaise, 9000);
    expect(day.cogsPaise, 7500);
    expect(day.grossProfitPaise, 1500);
    expect(day.billCount, 1);
    expect(day.items[rice.id]!.qtyMilli, 1500);
    expect(await all('khata'), isEmpty, reason: 'a paid bill never touches the khata');
  });

  test('the credit part of a split bill goes on the khata', () async {
    final bill = repo.createBill(
      cart: cartOf(1000),
      payment: const PaymentSplit(cashPaise: 1000, upiPaise: 2000, creditPaise: 3000),
      number: 'N2',
      customer: ravi,
    );
    await flush();
    expect(await balance(), 3000);
    final entry = (await all('khata')).single;
    expect(entry['amountPaise'], 3000);
    expect(entry['billId'], bill.id);
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.creditSalesPaise, 3000);
    expect(day.netCashPaise, 1000);
    expect(day.netUpiPaise, 2000);
  });

  test('an invalid bill writes nothing', () async {
    final before = await stock();
    expect(
      () => repo.createBill(
        cart: cartOf(1000),
        payment: const PaymentSplit(cashPaise: 1),
        number: 'bad',
      ),
      throwsA(isA<InvalidOperation>()),
    );
    await flush();
    expect(await stock(), before);
    expect(await all('bills'), isEmpty);
  });

  test('a custom line sells without touching stock or cost', () async {
    final cart = Cart()..addCustom('Bag', 500);
    repo.createBill(cart: cart, payment: const PaymentSplit(cashPaise: 500), number: 'N3');
    await flush();
    expect(await stock(), 10000);
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.salesPaise, 500);
    expect(day.cogsPaise, 0);
    expect(day.items, isEmpty);
  });

  test('voiding a bill restores everything to the original day', () async {
    final bill = repoFor(owner, at: DateTime(2026, 11, 8, 20)).createBill(
      cart: cartOf(1000),
      payment: const PaymentSplit(cashPaise: 1000, creditPaise: 5000),
      number: 'N4',
      customer: ravi,
    );
    await flush();
    repo.voidBill(bill, reason: 'wrong items');
    await flush();

    expect(await stock(), 10000);
    expect(await balance(), 0);
    final day = DayRollup.fromMap('2026-11-08', await doc('days/2026-11-08'));
    expect(day.salesPaise, 0);
    expect(day.billCount, 0);
    expect(day.cogsPaise, 0);
    expect(day.items[rice.id]!.qtyMilli, 0);
    expect((await doc('days/$today')), isEmpty, reason: 'today must be untouched');
    expect((await doc('bills/${bill.id}'))['voided'], isTrue);

    final voided = Bill.fromMap(bill.id, await doc('bills/${bill.id}'));
    expect(() => repo.voidBill(voided, reason: 'again'), throwsA(isA<InvalidOperation>()));
  });

  test('a void needs a reason', () async {
    final bill = repo.createBill(
        cart: cartOf(1000), payment: const PaymentSplit(cashPaise: 6000), number: 'N5');
    expect(() => repo.voidBill(bill, reason: '  '), throwsA(isA<InvalidOperation>()));
  });

  test('payments reduce dues, count as collections, and can leave an advance', () async {
    repo.recordKhataPurchase(customerId: ravi.id, amountPaise: 5000, note: 'old dues');
    repo.recordPayment(customerId: ravi.id, amountPaise: 2000, method: PaymentMethod.cash);
    repo.recordPayment(customerId: ravi.id, amountPaise: 4000, method: PaymentMethod.upi);
    await flush();
    expect(await balance(), -1000);
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.collectionCashPaise, 2000);
    expect(day.collectionUpiPaise, 4000);
    expect(day.salesPaise, 0, reason: 'collecting dues is not a sale');
  });

  test('credit is not a valid way to receive a payment', () {
    expect(
      () => repo.recordPayment(customerId: ravi.id, amountPaise: 1, method: PaymentMethod.credit),
      throwsA(isA<InvalidOperation>()),
    );
    expect(
      () => repo.recordPayment(customerId: ravi.id, amountPaise: 0, method: PaymentMethod.cash),
      throwsA(isA<InvalidOperation>()),
    );
  });

  test('reversing a payment restores dues and undoes the collection', () async {
    repo.recordKhataPurchase(customerId: ravi.id, amountPaise: 5000);
    final id = repo.recordPayment(customerId: ravi.id, amountPaise: 2000, method: PaymentMethod.cash);
    await flush();
    final entry = KhataEntry.fromMap(id, await doc('khata/$id'));
    repo.reverseKhataEntry(entry);
    await flush();

    expect(await balance(), 5000);
    final reversal = await doc('khata/rev_$id');
    expect(reversal['amountPaise'], 2000);
    expect(reversal['reversesId'], id);
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.collectionCashPaise, 0);
  });

  test('a bill-linked khata entry must be undone by voiding the bill', () async {
    final bill = repo.createBill(
        cart: cartOf(1000), payment: const PaymentSplit(creditPaise: 6000), number: 'N6', customer: ravi);
    await flush();
    final raw = (await db.collection('$storePath/khata').get()).docs.single;
    final entry = KhataEntry.fromMap(raw.id, raw.data());
    expect(entry.billId, bill.id);
    expect(() => repo.reverseKhataEntry(entry), throwsA(isA<InvalidOperation>()));
  });

  test('balance can be rebuilt from the ledger', () async {
    repo.recordKhataPurchase(customerId: ravi.id, amountPaise: 5000);
    repo.recordPayment(customerId: ravi.id, amountPaise: 1500, method: PaymentMethod.cash);
    await flush();
    await db.doc('$storePath/customers/${ravi.id}').update({'balancePaise': 999999});
    expect(await repo.recalculateCustomerBalance(ravi.id), 3500);
    expect(await balance(), 3500);
  });

  test('expenses count against profit and can be voided on their day', () async {
    final id = repo.addExpense(category: 'Rent', amountPaise: 100000, method: PaymentMethod.upi);
    await flush();
    var day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.expensePaise, 100000);
    expect(day.expenseUpiPaise, 100000);
    expect(day.netProfitPaise, -100000);

    repo.voidExpense(Expense.fromMap(id, await doc('expenses/$id')));
    await flush();
    day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.expensePaise, 0);
    expect((await doc('expenses/$id'))['voided'], isTrue);
  });

  test('a supplier purchase adds stock, updates cost, and tracks what is owed', () async {
    final supplierId = repo.saveSupplier(name: 'Wholesale');
    await flush();
    repo.recordSupplierPurchase(
      supplierId: supplierId,
      amountPaise: 110000,
      paidPaise: 10000,
      lines: [StockInLine(product: rice, qtyMilli: 20000, costPaise: 5500)],
    );
    await flush();

    expect(await stock(), 30000);
    expect((await doc('products/${rice.id}'))['costPaise'], 5500);
    expect((await doc('suppliers/$supplierId'))['balancePaise'], 100000);
    expect((await all('supplierTxns')), hasLength(2));
    var day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.purchasePaise, 110000);
    expect(day.supplierCashPaise, 10000);
    expect(day.netProfitPaise, 0, reason: 'stock bought is not an expense until it is sold');

    repo.recordSupplierPayment(supplierId: supplierId, amountPaise: 40000, method: PaymentMethod.upi);
    await flush();
    expect((await doc('suppliers/$supplierId'))['balancePaise'], 60000);
    day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.netUpiPaise, -40000);
  });

  test('paying a supplier more than the purchase is rejected', () {
    expect(
      () => repo.recordSupplierPurchase(supplierId: 'x', amountPaise: 100, paidPaise: 101),
      throwsA(isA<InvalidOperation>()),
    );
  });

  test('two offline devices selling the same item both count', () async {
    final a = repoFor(owner);
    final b = repoFor(cashier);
    a.createBill(cart: cartOf(9000), payment: const PaymentSplit(cashPaise: 54000), number: 'A1');
    b.createBill(cart: cartOf(4000), payment: const PaymentSplit(upiPaise: 24000), number: 'B1');
    await flush();
    expect(await stock(), -3000, reason: 'oversold stock shows as negative, not lost');
    final day = DayRollup.fromMap(today, await doc('days/$today'));
    expect(day.salesPaise, 78000);
    expect(day.billCount, 2);
  });

  test('saving a customer again does not reset the balance', () async {
    repo.recordKhataPurchase(customerId: ravi.id, amountPaise: 700);
    await flush();
    repo.saveCustomer(id: ravi.id, name: 'Ravi Kumar', creditLimitPaise: 5000);
    await flush();
    expect(await balance(), 700);
    expect((await doc('customers/${ravi.id}'))['name'], 'Ravi Kumar');
  });

  test('editing a product does not reset the stock', () async {
    repo.saveProduct(rice.copyPriceForTest(6500));
    await flush();
    expect(await stock(), 10000);
    expect((await doc('products/${rice.id}'))['pricePaise'], 6500);
  });

  test('cashier-only limits are enforced before writing', () {
    final till = repoFor(cashier);
    Matcher denied() => throwsA(isA<InvalidOperation>()
        .having((e) => e.code, 'code', 'manager_only'));
    expect(() => till.saveProduct(rice), denied());
    expect(() => till.adjustStock(productId: rice.id, deltaMilli: 1), denied());
    expect(() => till.saveSupplier(name: 'x'), denied());
    expect(() => till.archiveCustomer(ravi.id), denied());
    expect(
      () => till.recordAdjustment(customerId: ravi.id, signedPaise: 1, note: 'x'),
      denied(),
    );
  });

  test('streams hide archived records and sort by name', () async {
    repo.saveCustomer(name: 'zeb');
    final amma = repo.saveCustomer(name: 'Amma');
    final gone = repo.saveCustomer(name: 'Gone');
    await flush();
    repo.archiveCustomer(gone);
    await flush();
    final names = (await repo.customers().first).map((c) => c.name);
    expect(names, ['Amma', 'Ravi', 'zeb']);
    expect(amma, isNotEmpty);
  });

  test('khata stream returns one customer, newest first', () async {
    final other = repo.saveCustomer(name: 'Other');
    repoFor(owner, at: DateTime(2026, 11, 1)).recordKhataPurchase(customerId: ravi.id, amountPaise: 100);
    repoFor(owner, at: DateTime(2026, 11, 5)).recordKhataPurchase(customerId: ravi.id, amountPaise: 200);
    repo.recordKhataPurchase(customerId: other, amountPaise: 300);
    await flush();
    final entries = await repo.khata(ravi.id).first;
    expect(entries.map((e) => e.amountPaise), [200, 100]);
  });

  test('rollup stream covers an inclusive range of days', () async {
    for (final d in [1, 2, 3]) {
      repoFor(owner, at: DateTime(2026, 11, d, 10))
          .addExpense(category: 'x', amountPaise: 100, method: PaymentMethod.cash);
    }
    await flush();
    final list = await repo.days(from: '2026-11-02', to: '2026-11-03').first;
    expect(list.map((d) => d.dayKey).toList()..sort(), ['2026-11-02', '2026-11-03']);
  });
}

extension on Product {
  Product copyForTest(String newId) => Product(
        id: newId,
        name: name,
        unit: unit,
        pricePaise: pricePaise,
        costPaise: costPaise,
      );
  Product copyPriceForTest(int price) => Product(
        id: id,
        name: name,
        unit: unit,
        pricePaise: price,
        costPaise: costPaise,
      );
}
