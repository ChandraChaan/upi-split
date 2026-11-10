import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';

const owner = Actor(uid: 'u1', name: 'Owner', role: MemberRole.owner);
const cashier = Actor(uid: 'u2', name: 'Cashier', role: MemberRole.cashier);
const storePath = 'businesses/b/stores/s';
final now = DateTime(2026, 11, 10, 9, 15);
const today = '2026-11-10';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('CounterTape', () {
    test('typed amounts and one-tap amounts add up', () {
      final tape = CounterTape()
        ..digit('1')
        ..digit('0');
      expect(tape.typed, '10');
      expect(tape.totalPaise, 1000, reason: 'Typed but not yet added still counts');
      tape
        ..add(2)
        ..add(1);
      expect(tape.entries.map((e) => e.totalPaise), [1000, 200, 100]);
      expect(tape.typed, isEmpty);
      expect(tape.totalPaise, 1300);
    });

    test('price times count', () {
      final tape = CounterTape()
        ..digit('2')
        ..multiply()
        ..digit('5');
      expect(tape.typed, '2×5');
      expect(tape.totalPaise, 1000);
      expect(tape.commit(), isTrue);
      expect(tape.entries.single.pricePaise, 200);
      expect(tape.entries.single.count, 5);
    });

    test('a price with × but no count yet counts once', () {
      final tape = CounterTape()
        ..digit('7')
        ..multiply();
      expect(tape.totalPaise, 700);
      tape.multiply();
      expect(tape.typed, '7×', reason: 'Only one ×');
    });

    test('leading zeros, empty × and long numbers are ignored', () {
      final tape = CounterTape()
        ..digit('0')
        ..digit('00')
        ..multiply();
      expect(tape.typed, isEmpty);
      for (var i = 0; i < 9; i++) {
        tape.digit('9');
      }
      expect(tape.typed, '999999');
      tape
        ..clear()
        ..digit('5')
        ..digit('0')
        ..digit('00');
      expect(tape.typed, '5000');
    });

    test('backspace, then clear typed, then clear the whole sale', () {
      final tape = CounterTape()
        ..add(5)
        ..digit('1')
        ..digit('2')
        ..backspace();
      expect(tape.typed, '1');
      tape.clear();
      expect(tape.typed, isEmpty);
      expect(tape.entries, hasLength(1));
      tape.clear();
      expect(tape.isEmpty, isTrue);
    });

    test('takeAll includes what is typed and empties the tape', () {
      final tape = CounterTape()
        ..add(2)
        ..digit('3');
      final all = tape.takeAll();
      expect(all.map((e) => e.totalPaise), [200, 300]);
      expect(tape.isEmpty, isTrue);
    });
  });

  group('CounterPayment', () {
    test('paying nothing puts the whole sale on credit', () {
      final p = CounterPayment.settle(totalPaise: 5000, paidPaise: 0);
      expect(p.split.creditPaise, 5000);
      expect(p.split.cashPaise, 0);
      expect(p.towardsDuesPaise, 0);
    });

    test('a part payment splits between paid and credit', () {
      final p = CounterPayment.settle(
        totalPaise: 20000,
        paidPaise: 15000,
        method: PaymentMethod.upi,
      );
      expect(p.split.upiPaise, 15000);
      expect(p.split.creditPaise, 5000);
      expect(p.split.totalPaise, 20000);
    });

    test('paying more than the sale clears earlier dues', () {
      final p = CounterPayment.settle(totalPaise: 3000, paidPaise: 10000);
      expect(p.split.cashPaise, 3000);
      expect(p.split.creditPaise, 0);
      expect(p.towardsDuesPaise, 7000);
    });
  });

  group('repository', () {
    late FakeFirebaseFirestore db;
    late StoreRepository repo;
    late Customer ravi;

    StoreRepository repoFor(Actor actor) => StoreRepository(
          db,
          businessId: 'b',
          storeId: 's',
          actor: actor,
          clock: () => now,
        );

    Future<Map<String, dynamic>> doc(String path) async =>
        (await db.doc('$storePath/$path').get()).data() ?? {};
    Future<List<Map<String, dynamic>>> all(String name) async =>
        (await db.collection('$storePath/$name').get()).docs.map((d) => d.data()).toList();

    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = repoFor(owner);
      final id = repo.saveCustomer(name: 'Ravi');
      repo.recordKhataPurchase(customerId: id, amountPaise: 12000);
      await flush();
      ravi = Customer(id: id, name: 'Ravi', balancePaise: 12000);
    });

    test('a cash counter sale is a bill of free-form lines', () async {
      final sale = repo.sellAtCounter(
        entries: const [TapeEntry(1000), TapeEntry(200, 5)],
        payment: CounterPayment.settle(totalPaise: 2000, paidPaise: 2000),
        number: 'N1',
        itemName: 'Items',
        itemNameTe: 'సరుకులు',
      );
      await flush();
      final bill = await doc('bills/${sale.bill.id}');
      expect(bill['totalPaise'], 2000);
      expect(bill['cashPaise'], 2000);
      final items = (bill['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((i) => i['qtyMilli']), [1000, 5000]);
      expect(items.every((i) => i['productId'] == null), isTrue);
      expect(await all('stockMoves'), isEmpty);
      final day = await doc('days/$today');
      expect(day['salesPaise'], 2000);
      expect(day['billCount'], 1);
      expect(day['cogsPaise'], 0);
    });

    test('a part-paid sale puts the rest on the khata', () async {
      repo.sellAtCounter(
        entries: const [TapeEntry(20000)],
        payment: CounterPayment.settle(totalPaise: 20000, paidPaise: 5000),
        number: 'N2',
        itemName: 'Items',
        customer: ravi,
      );
      await flush();
      expect((await doc('customers/${ravi.id}'))['balancePaise'], 12000 + 15000);
      final day = await doc('days/$today');
      expect(day['cashSalesPaise'], 5000);
      expect(day['creditSalesPaise'], 15000);
    });

    test('paying extra comes off old dues and counts as a collection', () async {
      final sale = repo.sellAtCounter(
        entries: const [TapeEntry(3000)],
        payment: CounterPayment.settle(
          totalPaise: 3000,
          paidPaise: 10000,
          method: PaymentMethod.upi,
        ),
        number: 'N3',
        itemName: 'Items',
        customer: ravi,
        method: PaymentMethod.upi,
      );
      await flush();
      expect(sale.paymentPaise, 7000);
      expect((await doc('customers/${ravi.id}'))['balancePaise'], 12000 - 7000);
      final day = await doc('days/$today');
      expect(day['upiSalesPaise'], 3000);
      expect(day['collectionUpiPaise'], 7000);

      repo.undoCounterSale(sale, reason: 'Undo');
      await flush();
      expect((await doc('customers/${ravi.id}'))['balancePaise'], 12000);
      final after = await doc('days/$today');
      expect(after['salesPaise'], 0);
      expect(after['collectionUpiPaise'], 0);
      expect((await doc('bills/${sale.bill.id}'))['voided'], isTrue);
    });

    test('undo of a credit sale takes it off the khata', () async {
      final sale = repo.sellAtCounter(
        entries: const [TapeEntry(4000)],
        payment: CounterPayment.settle(totalPaise: 4000, paidPaise: 0),
        number: 'N4',
        itemName: 'Items',
        customer: ravi,
      );
      await flush();
      repo.undoCounterSale(sale, reason: 'Undo');
      await flush();
      expect((await doc('customers/${ravi.id}'))['balancePaise'], 12000);
    });

    test('credit needs a customer, and only managers undo', () {
      expect(
        () => repo.sellAtCounter(
          entries: const [TapeEntry(100)],
          payment: CounterPayment.settle(totalPaise: 100, paidPaise: 0),
          number: 'N5',
          itemName: 'Items',
        ),
        throwsA(isA<InvalidOperation>()),
      );
      final sale = repoFor(cashier).sellAtCounter(
        entries: const [TapeEntry(100)],
        payment: CounterPayment.settle(totalPaise: 100, paidPaise: 100),
        number: 'N6',
        itemName: 'Items',
      );
      expect(
        () => repoFor(cashier).undoCounterSale(sale, reason: 'Undo'),
        throwsA(isA<InvalidOperation>()),
      );
    });

    test('a morning purchase adds the wholesaler, the list and the auto fare', () async {
      final supplierId = repo.recordMarketPurchase(
        supplierName: ' Ganesh Wholesale ',
        amountPaise: 450000,
        paidPaise: 400000,
        items: const [
          PurchaseLine(name: 'Rice 25 kg', amountPaise: 150000),
          PurchaseLine(name: 'Biscuits'),
          PurchaseLine(name: '  '),
        ],
        transportPaise: 15000,
      );
      await flush();

      final supplier = await doc('suppliers/$supplierId');
      expect(supplier['name'], 'Ganesh Wholesale');
      expect(supplier['balancePaise'], 50000, reason: '₹500 still owed');
      final txns = await all('supplierTxns');
      final purchase = txns.firstWhere((t) => t['kind'] == 'purchase');
      expect(purchase['items'], [
        {'name': 'Rice 25 kg', 'amountPaise': 150000},
        {'name': 'Biscuits', 'amountPaise': 0},
      ]);
      expect(txns.where((t) => t['kind'] == 'payment').single['amountPaise'], 400000);
      final expense = (await all('expenses')).single;
      expect(expense['category'], 'transport');
      expect(expense['amountPaise'], 15000);
      final day = await doc('days/$today');
      expect(day['purchasePaise'], 450000);
      expect(day['supplierCashPaise'], 400000);
      expect(day['expenseCashPaise'], 15000);

      final recent = await repo.recentPurchases().first;
      expect(recent.single.items, hasLength(2));
      expect(recent.single.items.first.name, 'Rice 25 kg');
    });

    test('a purchase from a saved wholesaler does not add another', () async {
      final id = repo.saveSupplier(name: 'Ganesh');
      repo.recordMarketPurchase(supplierId: id, amountPaise: 1000, paidPaise: 1000);
      await flush();
      expect(await all('suppliers'), hasLength(1));
      expect(await all('expenses'), isEmpty);
      expect(
        () => repo.recordMarketPurchase(amountPaise: 1000, paidPaise: 0),
        throwsA(isA<InvalidOperation>()),
        reason: 'A new wholesaler needs a name',
      );
    });
  });
}
