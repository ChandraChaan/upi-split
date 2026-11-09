import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/customer_detail_screen.dart';

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
    'recording the full amount clears dues and the due date at once',
    (t) async {
      final h = await pumpApp(t, role: MemberRole.cashier);
      await h.tab('Khata');
      expect(find.text('Overdue'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('customer_c1')));
      await settle(t);
      expect(find.text('₹800'), findsWidgets);

      await tapKey(t, 'record_payment');
      await tapKey(t, 'payment_full');
      await t.tap(find.text('UPI'));
      await settle(t);
      await tapKey(t, 'payment_save');

      expect(find.text('Payment received'), findsOneWidget);
      expect(find.text('Balance ₹0'), findsOneWidget);
      final customer = await h.doc('customers/c1');
      expect(customer['balancePaise'], 0);
      expect(customer['dueDate'], isNull);
      final entry = (await h.collection('khata')).single;
      expect(entry['amountPaise'], -80000);
      expect(entry['method'], 'upi');
      final day = await h.doc('days/${dayKey(DateTime.now())}');
      expect(day['collectionUpiPaise'], 80000);
    },
  );

  testWidgets(
    'a part payment keeps the due date and an empty amount is refused',
    (t) async {
      final h = await pumpApp(t);
      await h.open(const CustomerDetailScreen(customerId: 'c1'));
      await tapKey(t, 'record_payment');

      await tapKey(t, 'payment_save');
      expect(find.text('Required'), findsOneWidget);
      expect(await h.collection('khata'), isEmpty);

      await t.enterText(find.byKey(const Key('payment_amount')), '300');
      await tapKey(t, 'payment_save');
      final customer = await h.doc('customers/c1');
      expect(customer['balancePaise'], 50000);
      expect(customer['dueDate'], isNotNull);
    },
  );

  Future<void> addEntries(FirebaseFirestore db) async {
    Future<void> entry(String id, Map<String, Object?> extra) =>
        db.doc('$storePath/khata/$id').set({
          'customerId': 'c1',
          'kind': 'purchase',
          'amountPaise': 1000,
          'method': 'credit',
          'billId': null,
          'note': '',
          'reversesId': null,
          'at': Timestamp.now(),
          'byUid': 'u1',
          'byName': 'Ravi',
          ...extra,
        });
    await entry('plain', {'note': 'plain entry'});
    await entry('linked', {'billId': 'bill1', 'note': 'linked entry'});
    await entry('done', {'note': 'already reversed'});
    await entry('rev_done', {
      'amountPaise': -1000,
      'reversesId': 'done',
      'note': 'the reversal',
    });
  }

  testWidgets('reverse is offered only on entries that can be reversed', (
    t,
  ) async {
    final h = await pumpApp(t, beforeStart: addEntries);
    await h.open(const CustomerDetailScreen(customerId: 'c1'));

    expect(find.byKey(const ValueKey('reverse_plain')), findsOneWidget);
    expect(find.byKey(const ValueKey('reverse_linked')), findsNothing);
    expect(find.byKey(const ValueKey('reverse_done')), findsNothing);
    expect(find.byKey(const ValueKey('reverse_rev_done')), findsNothing);

    await t.ensureVisible(find.byKey(const ValueKey('reverse_plain')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('reverse_plain')));
    await settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Reverse'));
    await settle(t);

    expect((await h.doc('khata/rev_plain'))['amountPaise'], -1000);
    expect((await h.doc('customers/c1'))['balancePaise'], 79000);
    expect(find.byKey(const ValueKey('reverse_plain')), findsNothing);
  });

  testWidgets('a cashier cannot adjust or reverse, or change a credit limit', (
    t,
  ) async {
    final h = await pumpApp(
      t,
      role: MemberRole.cashier,
      beforeStart: addEntries,
    );
    await h.open(const CustomerDetailScreen(customerId: 'c1'));
    expect(find.byKey(const Key('khata_adjust')), findsNothing);
    expect(find.byKey(const ValueKey('reverse_plain')), findsNothing);
    expect(find.text('Credit limit: ₹1,000'), findsNothing);

    await tapKey(t, 'customer_edit');
    expect(find.byKey(const Key('customer_limit')), findsNothing);
    await t.enterText(find.byKey(const Key('customer_name')), 'Suresh Babu');
    await tapKey(t, 'customer_save');
    final customer = await h.doc('customers/c1');
    expect(customer['name'], 'Suresh Babu');
    expect(
      customer['creditLimitPaise'],
      100000,
      reason: 'Rules reject a cashier changing this',
    );
  });

  testWidgets('a bad phone number is refused on the customer form', (t) async {
    final h = await pumpApp(t);
    await h.tab('Khata');
    await tapKey(t, 'khata_add_customer');
    await t.enterText(find.byKey(const Key('customer_name')), 'Lata');
    await t.enterText(find.byKey(const Key('customer_phone')), '12345');
    await tapKey(t, 'customer_save');
    expect(find.text('Enter a 10-digit mobile number'), findsOneWidget);
    expect((await h.collection('customers')).length, 2);
  });
}
