import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/receipt_screen.dart';

import 'support/harness.dart';

void main() {
  setUpAll(setUpStrings);

  Future<void> tapKey(WidgetTester t, String key) async {
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pump();
    await t.tap(find.byKey(Key(key)));
    await settle(t);
  }

  testWidgets(
    'a cash sale saves and shows the receipt without any network wait',
    (t) async {
      final h = await pumpApp(t, role: MemberRole.cashier);
      await h.itemBilling();

      await t.tap(find.byKey(const ValueKey('product_soap')));
      await settle(t);
      await t.tap(find.byKey(const ValueKey('plus_soap')));
      await settle(t);
      expect(find.text('₹80'), findsOneWidget, reason: 'Two soaps at ₹40');

      await tapKey(t, 'billing_checkout');
      await t.enterText(find.byKey(const Key('cash_tendered')), '100');
      await settle(t);
      expect(find.text('Change to give'), findsOneWidget);
      expect(find.text('₹20'), findsOneWidget);

      await tapKey(t, 'checkout_save');
      expect(find.byType(ReceiptView), findsOneWidget);
      expect(find.text('Lakshmi Kirana'), findsOneWidget);
      expect(find.text('Lux Soap'), findsOneWidget);

      final bills = await h.collection('bills');
      expect(bills, hasLength(1));
      expect(bills.single['totalPaise'], 8000);
      expect(bills.single['cashPaise'], 8000);
      expect((await h.doc('products/soap'))['stockMilli'], 8000);
      final day = await h.doc('days/${dayKey(DateTime.now())}');
      expect(day['salesPaise'], 120000 + 8000);

      await tapKey(t, 'receipt_new_bill');
      expect(find.byKey(const Key('billing_search')), findsOneWidget);
      expect(
        find.byKey(const Key('billing_checkout')),
        findsNothing,
        reason: 'Cart is cleared',
      );
    },
  );

  testWidgets('a scanned barcode adds the product and clears the field', (
    t,
  ) async {
    final h = await pumpApp(t);
    await h.itemBilling();

    await t.enterText(find.byKey(const Key('billing_search')), '8901000000028');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await settle(t);

    expect(find.byKey(const ValueKey('plus_soap')), findsOneWidget);
    final field = t.widget<TextField>(find.byKey(const Key('billing_search')));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('search matches English and Telugu names', (t) async {
    final h = await pumpApp(t);
    await h.itemBilling();
    await t.enterText(find.byKey(const Key('billing_search')), 'సబ్బు');
    await settle(t);
    expect(find.byKey(const ValueKey('product_soap')), findsOneWidget);
    expect(find.byKey(const ValueKey('product_rice')), findsNothing);

    await t.enterText(find.byKey(const Key('billing_search')), 'sona');
    await settle(t);
    expect(find.byKey(const ValueKey('product_rice')), findsOneWidget);
    expect(find.byKey(const ValueKey('product_soap')), findsNothing);
  });

  testWidgets(
    'loose goods take decimal quantities, and one-off lines and discount apply',
    (t) async {
      final h = await pumpApp(t);
      await h.itemBilling();

      await t.tap(find.byKey(const ValueKey('product_rice')));
      await settle(t);
      await t.enterText(find.byKey(const Key('line_qty')), '1.5');
      await tapKey(t, 'line_done');
      expect(find.text('₹90'), findsOneWidget, reason: '1.5 kg at ₹60');

      await t.tap(find.byKey(const Key('add_custom_line')));
      await settle(t);
      await t.enterText(find.byKey(const Key('custom_name')), 'Carry bag');
      await t.enterText(find.byKey(const Key('custom_price')), '10');
      await tapKey(t, 'custom_done');

      await tapKey(t, 'billing_checkout');
      await t.enterText(find.byKey(const Key('checkout_discount')), '5');
      await settle(t);
      await tapKey(t, 'pay_upi');
      await tapKey(t, 'checkout_save');

      final bill = (await h.collection('bills')).single;
      expect(bill['subtotalPaise'], 10000);
      expect(bill['discountPaise'], 500);
      expect(bill['totalPaise'], 9500);
      expect(bill['upiPaise'], 9500);
      expect((await h.doc('products/rice'))['stockMilli'], 48500);
    },
  );

  testWidgets(
    'all credit needs a customer; quick-add one and write to the khata',
    (t) async {
      final h = await pumpApp(t);
      await h.itemBilling();
      await t.tap(find.byKey(const ValueKey('product_soap')));
      await settle(t);
      await tapKey(t, 'billing_checkout');

      await tapKey(t, 'pay_credit');
      await t.tap(find.byKey(const Key('quick_add_customer')));
      await settle(t);
      await t.enterText(find.byKey(const Key('quick_customer_name')), 'Kumar');
      await t.enterText(
        find.byKey(const Key('quick_customer_phone')),
        '9812345678',
      );
      await tapKey(t, 'quick_customer_save');

      await tapKey(t, 'checkout_save');
      expect(find.byType(ReceiptView), findsOneWidget);
      expect(find.byKey(const Key('share_whatsapp')), findsOneWidget);

      final bill = (await h.collection('bills')).single;
      expect(bill['creditPaise'], 4000);
      final khata = (await h.collection('khata')).single;
      expect(khata['amountPaise'], 4000);
      expect(khata['customerId'], bill['customerId']);
    },
  );

  testWidgets('going over the credit limit warns and can be overridden', (
    t,
  ) async {
    final h = await pumpApp(t);
    await h.itemBilling();
    for (var i = 0; i < 6; i++) {
      await t.tap(find.byKey(const ValueKey('product_soap')));
      await settle(t);
    }
    await tapKey(t, 'billing_checkout');
    await tapKey(t, 'pay_credit');
    await t.tap(find.byKey(const ValueKey('pick_customer_c1')));
    await settle(t);
    expect(
      find.text('This bill goes over the credit limit of ₹1,000'),
      findsOneWidget,
    );

    await tapKey(t, 'checkout_save');
    expect(find.text('Over the credit limit'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await settle(t);
    expect(await h.collection('bills'), isEmpty);

    await tapKey(t, 'checkout_save');
    await t.tap(find.text('Save anyway'));
    await settle(t);
    expect((await h.collection('bills')).single['creditPaise'], 24000);
    expect((await h.doc('customers/c1'))['balancePaise'], 80000 + 24000);
  });

  testWidgets('a split must add up before it can be saved', (t) async {
    final h = await pumpApp(t);
    await h.itemBilling();
    await t.tap(find.byKey(const ValueKey('product_soap')));
    await settle(t);
    await tapKey(t, 'billing_checkout');
    await tapKey(t, 'pay_split');

    await t.enterText(find.byKey(const Key('split_upi')), '10');
    await settle(t);
    final cash = t.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('split_cash')),
        matching: find.byType(EditableText),
      ),
    );
    expect(cash.controller.text, '30', reason: 'Cash takes up the rest');

    await t.enterText(find.byKey(const Key('split_cash')), '5');
    await settle(t);
    expect(find.text('₹25 still to allot'), findsOneWidget);
    await tapKey(t, 'checkout_save');
    expect(await h.collection('bills'), isEmpty);
    expect(
      find.text('The payments do not add up to the bill total'),
      findsOneWidget,
    );
  });
}
