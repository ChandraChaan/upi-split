import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';

import 'support/harness.dart';

void main() {
  setUpAll(setUpStrings);

  Future<void> tap(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pump();
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  Future<void> type(WidgetTester t, String digits) async {
    for (final d in digits.split('')) {
      await tap(t, d == '×' ? 'key_times' : 'key_$d');
    }
  }

  String total(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('sell_total'))).data!;

  final today = dayKey(DateTime.now());

  // Phone heights from small to tall; an overflow fails the test.
  for (final size in const [
    Size(320, 568),
    Size(360, 640),
    Size(411, 731),
    Size(412, 915),
  ]) {
    for (final language in ['te', 'en']) {
      testWidgets('the keypad fits $size in $language', (t) async {
        await pumpApp(t, size: size, language: language);
        await tap(t, 'quick_50');
        await type(t, '12×3');
        expect(find.byKey(const Key('sell_total')), findsOneWidget);
        expect(find.byKey(const Key('key_add')), findsOneWidget);
        expect(find.byKey(const Key('sell_later')), findsOneWidget);
      });
    }
  }

  testWidgets('tapping ₹1 and ₹2 and typing amounts makes a cash sale', (
    t,
  ) async {
    final h = await pumpApp(t, role: MemberRole.cashier);
    await type(t, '10');
    await tap(t, 'key_add');
    await tap(t, 'quick_2');
    await tap(t, 'quick_1');
    expect(total(t), '₹13');

    await tap(t, 'sell_cash');
    expect(find.text('₹13 Cash saved'), findsOneWidget);
    expect(
      find.byType(SnackBar),
      findsNothing,
      reason: 'Pay buttons stay clear',
    );
    expect(find.byKey(const Key('sell_undo')), findsNothing);
    expect(total(t), '₹0');
    await tap(t, 'quick_1');
    expect(find.text('₹13 Cash saved'), findsNothing);

    final bill = (await h.collection('bills')).single;
    expect(bill['totalPaise'], 1300);
    expect(bill['cashPaise'], 1300);
    expect((bill['items'] as List).length, 3);
    expect((await h.doc('days/$today'))['salesPaise'], 120000 + 1300);
  });

  testWidgets('price times count, paid by UPI', (t) async {
    final h = await pumpApp(t);
    await type(t, '2×5');
    expect(find.text('+ ₹2 × 5'), findsOneWidget);
    expect(total(t), '₹10');
    await tap(t, 'sell_upi');

    final bill = (await h.collection('bills')).single;
    expect(bill['upiPaise'], 1000);
    final line = (bill['items'] as List).single as Map;
    expect(line['qtyMilli'], 5000);
    expect(line['pricePaise'], 200);
  });

  testWidgets('a wrong amount is removed from the tape', (t) async {
    await pumpApp(t);
    await tap(t, 'quick_5');
    await tap(t, 'quick_2');
    await t.tap(find.byTooltip('Remove ₹5'));
    await settle(t);
    expect(total(t), '₹2');
  });

  testWidgets('pay later with part paid puts the rest on the khata', (t) async {
    final h = await pumpApp(t);
    await type(t, '200');
    await tap(t, 'sell_later');
    await t.tap(find.byKey(const ValueKey('pick_customer_c2')));
    await settle(t);

    await t.enterText(find.byKey(const Key('paylater_paid')), '150');
    await settle(t);
    expect(find.text('Goes on khata'), findsOneWidget);
    await tap(t, 'paylater_save');
    expect(find.text("₹50 added to Anitha's khata"), findsOneWidget);

    final bill = (await h.collection('bills')).single;
    expect(bill['cashPaise'], 15000);
    expect(bill['creditPaise'], 5000);
    expect(bill['customerId'], 'c2');
    expect((await h.doc('customers/c2'))['balancePaise'], 5000);
  });

  testWidgets('a new customer can be added by name alone, paying nothing', (
    t,
  ) async {
    final h = await pumpApp(t);
    await tap(t, 'quick_20');
    await tap(t, 'sell_later');
    await t.tap(find.byKey(const Key('quick_add_customer')));
    await settle(t);
    await t.enterText(find.byKey(const Key('quick_customer_name')), 'Ramu');
    await tap(t, 'quick_customer_save');
    await tap(t, 'paylater_save');

    final bill = (await h.collection('bills')).single;
    expect(bill['creditPaise'], 2000);
    expect(bill['customerName'], 'Ramu');
  });

  testWidgets('paying more than the sale clears old dues', (t) async {
    final h = await pumpApp(t);
    await type(t, '30');
    await tap(t, 'sell_later');
    await t.tap(find.byKey(const ValueKey('pick_customer_c1')));
    await settle(t);
    await t.enterText(find.byKey(const Key('paylater_paid')), '100');
    await settle(t);
    expect(find.text('Off old dues'), findsOneWidget);
    await tap(t, 'paylater_save');

    expect((await h.doc('customers/c1'))['balancePaise'], 80000 - 7000);
    final bill = (await h.collection('bills')).single;
    expect(bill['cashPaise'], 3000);
    expect(bill['creditPaise'], 0);
    final day = await h.doc('days/$today');
    expect(day['collectionCashPaise'], 7000);
  });

  testWidgets('the owner can undo a sale made by mistake', (t) async {
    final h = await pumpApp(t);
    await tap(t, 'quick_10');
    await tap(t, 'sell_cash');
    expect(find.text('₹10 Cash saved'), findsOneWidget);
    await t.tap(find.byKey(const Key('sell_undo')));
    await settle(t);

    expect((await h.collection('bills')).single['voided'], isTrue);
    expect((await h.doc('days/$today'))['salesPaise'], 120000);
    expect(find.text('Sale taken back'), findsOneWidget);
  });

  testWidgets('itemised billing is still one tap away', (t) async {
    final h = await pumpApp(t);
    await h.itemBilling();
    expect(find.byKey(const Key('billing_search')), findsOneWidget);
  });

  testWidgets('the morning wholesale purchase, with a new shop', (t) async {
    final h = await pumpApp(t);
    await h.tab('Today');
    await tap(t, 'quick_market_purchase');
    expect(
      t
          .widget<ChoiceChip>(find.byKey(const ValueKey('market_shop_v1')))
          .selected,
      isTrue,
      reason: 'The only saved supplier is chosen',
    );

    await tap(t, 'market_new_shop');
    await t.enterText(
      find.byKey(const Key('market_shop_name')),
      'Ganesh Wholesale',
    );
    await tap(t, 'market_add_item');
    await t.enterText(find.byKey(const ValueKey('market_item_0')), 'Rice bag');
    await t.enterText(
      find.byKey(const ValueKey('market_item_amount_0')),
      '1500',
    );
    await settle(t);
    expect(find.text('Added up from the list'), findsOneWidget);

    await t.enterText(find.byKey(const Key('market_total')), '4500');
    await tap(t, 'market_paid_full');
    await t.enterText(find.byKey(const Key('market_paid')), '4000');
    await settle(t);
    expect(find.text('Still owed to them: ₹500'), findsOneWidget);
    await t.enterText(find.byKey(const Key('market_transport')), '150');
    await tap(t, 'market_save');
    expect(find.text('Purchase saved'), findsOneWidget);

    final suppliers = await h.collection('suppliers');
    final ganesh = suppliers.firstWhere((s) => s['name'] == 'Ganesh Wholesale');
    expect(ganesh['balancePaise'], 50000);
    final purchase = (await h.collection(
      'supplierTxns',
    )).firstWhere((x) => x['kind'] == 'purchase');
    expect(purchase['amountPaise'], 450000);
    expect(purchase['items'], [
      {'name': 'Rice bag', 'amountPaise': 150000},
    ]);
    final expense = (await h.collection('expenses')).single;
    expect(expense['category'], 'transport');
    expect(expense['amountPaise'], 15000);
    expect(find.text('₹4,500'), findsWidgets, reason: 'Bought today');
  });

  testWidgets('a purchase total can come from the list alone', (t) async {
    final h = await pumpApp(t, role: MemberRole.manager);
    await h.tab('More');
    await tap(t, 'more_purchases');
    expect(find.textContaining('No purchases yet'), findsOneWidget);
    await tap(t, 'purchases_add');
    await tap(t, 'market_add_item');
    await t.enterText(find.byKey(const ValueKey('market_item_0')), 'Oil');
    await t.enterText(
      find.byKey(const ValueKey('market_item_amount_0')),
      '800',
    );
    await settle(t);
    await tap(t, 'market_save');

    final purchase = (await h.collection(
      'supplierTxns',
    )).firstWhere((x) => x['kind'] == 'purchase');
    expect(purchase['supplierId'], 'v1');
    expect(purchase['amountPaise'], 80000);
    expect(find.text('Sri Venkateswara Agencies'), findsOneWidget);
  });
}
