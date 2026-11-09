import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kirana_admin/shell/admin_shell.dart';
import 'package:kirana_core/kirana_core.dart';

import 'test_helpers.dart';

Future<void> seedEverything(FirebaseFirestore db) async {
  await seedSales(db, 's1');
  await seedSales(db, 's2', sales: 50000, cogs: 20000);
  final store = db.doc('businesses/$businessId/stores/s1');
  final now = Timestamp.fromDate(DateTime.now());
  await store.collection('khata').doc('k1').set({
    'customerId': 'c1',
    'kind': 'purchase',
    'amountPaise': 45000,
    'method': 'credit',
    'at': now,
    'byUid': 'u1',
    'byName': 'Ravi',
    'note': 'Monthly goods',
  });
  await store.collection('bills').doc('b1').set({
    'number': '261109-K7-1',
    'items': [
      {
        'productId': 'p1',
        'name': 'Toor Dal',
        'nameTe': 'కందిపప్పు',
        'unit': 'kg',
        'qtyMilli': 2000,
        'pricePaise': 20000,
        'costPaise': 15000,
        'totalPaise': 40000,
      },
    ],
    'subtotalPaise': 40000,
    'discountPaise': 0,
    'totalPaise': 40000,
    'cashPaise': 40000,
    'upiPaise': 0,
    'creditPaise': 0,
    'at': now,
    'dayKey': dayKey(DateTime.now()),
    'byUid': 'u1',
    'byName': 'Ravi',
    'customerName': 'Sita',
    'voided': false,
  });
  await store.collection('expenses').doc('e1').set({
    'category': 'Rent',
    'amountPaise': 8000,
    'method': 'cash',
    'at': now,
    'dayKey': dayKey(DateTime.now()),
    'byUid': 'u1',
    'byName': 'Ravi',
    'voided': false,
  });
  await store.collection('suppliers').doc('v1').set({
    'name': 'Sri Traders',
    'phone': '9876500000',
    'balancePaise': 100000,
    'archived': false,
  });
  await store.collection('supplierTxns').doc('t1').set({
    'supplierId': 'v1',
    'kind': 'purchase',
    'amountPaise': 100000,
    'at': now,
    'byName': 'Ravi',
  });
  await store.collection('stockMoves').doc('m1').set({
    'productId': 'p1',
    'deltaMilli': -2000,
    'reason': 'sale',
    'at': now,
    'byName': 'Ravi',
  });
  await db.doc('businesses/$businessId/members/m2').set({
    'name': 'Kumar',
    'email': 'kumar@example.com',
    'role': 'cashier',
    'storeIds': ['s1'],
    'active': true,
  });
  await db.doc('invites/ABCD2345').set({
    'businessId': businessId,
    'businessName': 'Lakshmi Traders',
    'role': 'cashier',
    'storeIds': ['s1'],
    'createdBy': 'u1',
    'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 5))),
    'usedBy': null,
  });
}

const routes = [
  '/dashboard',
  '/customers',
  '/customers/s1/c1',
  '/products',
  '/products/import',
  '/products/s1/p1',
  '/bills',
  '/bills/s1/b1',
  '/suppliers',
  '/suppliers/s1/v1',
  '/expenses',
  '/reports',
  '/staff',
  '/stores',
  '/settings',
];

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void go(WidgetTester tester, String path) {
  GoRouter.of(tester.element(find.byType(AdminShell))).go(path);
}

/// Taps inside the top-most dialog, where a button with the same label may
/// also exist on the page behind it.
Finder inDialog(Finder finder) =>
    find.descendant(of: find.byType(AlertDialog), matching: finder);

void main() {
  for (final (width, height) in const [(360.0, 800.0), (1400.0, 900.0)]) {
    for (final language in const ['en', 'te']) {
      testWidgets('every page renders at ${width.toInt()}px in $language', (tester) async {
        useViewport(tester, width, height);
        final harness = await buildHarness(role: MemberRole.owner, language: language, seed: seedEverything);
        await pumpApp(tester, harness);
        for (final route in routes) {
          go(tester, route);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'at $route');
          expect(find.byIcon(Icons.error_outline), findsNothing, reason: 'error state at $route');
        }
      });
    }
  }

  testWidgets('each report opens and its table sorts', (tester) async {
    useViewport(tester, 1400, 1200);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/reports');
    await settle(tester);
    for (final name in const [
      'Payment modes',
      'Collections',
      'Product sales',
      'Dues ageing',
      'Store comparison',
      'Daily profit and loss',
    ]) {
      await tester.tap(find.widgetWithText(ChoiceChip, name));
      await settle(tester);
      expect(tester.takeException(), isNull, reason: name);
      expect(find.byIcon(Icons.error_outline), findsNothing, reason: name);
    }
    await tester.tap(find.text('Sales').last);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add customer validates, then writes through the repository', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    harness.scope.select('s1');
    await pumpApp(tester, harness);
    go(tester, '/customers');
    await settle(tester);

    await tester.tap(find.text('Add customer').first);
    await settle(tester);
    await tester.tap(inDialog(find.text('Save')));
    await settle(tester);
    expect(inDialog(find.text('Required')), findsWidgets);

    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Name')), 'Gopal');
    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Phone')), '123');
    await tester.tap(inDialog(find.text('Save')));
    await settle(tester);
    expect(inDialog(find.text('Enter a 10-digit mobile number')), findsOneWidget);

    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Phone')), '9988776655');
    await tester.tap(inDialog(find.text('Save')));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Gopal'), findsOneWidget);
    final docs = await harness.db.collection('businesses/$businessId/stores/s1/customers').get();
    expect(docs.docs.map((d) => d.data()['name']), contains('Gopal'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('record payment reduces the balance and logs a collection', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/customers/s1/c1');
    await settle(tester);

    await tester.tap(find.text('Record payment'));
    await settle(tester);
    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Amount')), '100.50');
    await tester.tap(inDialog(find.text('Save')));
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    final store = 'businesses/$businessId/stores/s1';
    final customer = await harness.db.doc('$store/customers/c1').get();
    expect(customer.data()!['balancePaise'], 45000 - 10050);
    final day = await harness.db.doc('$store/days/${dayKey(DateTime.now())}').get();
    expect(day.data()!['collectionCashPaise'], 10000 + 10050);
    expect(find.text('Payment'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('voiding a bill needs a reason', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/bills/s1/b1');
    await settle(tester);

    await tester.tap(find.text('Void bill').first);
    await settle(tester);
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Void')));
    await settle(tester);
    expect(inDialog(find.text('Required')), findsOneWidget);

    await tester.enterText(inDialog(find.widgetWithText(TextFormField, 'Reason')), 'Wrong items');
    await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Void')));
    await settle(tester);
    final bill = await harness.db.doc('businesses/$businessId/stores/s1/bills/b1').get();
    expect(bill.data()!['voided'], isTrue);
    expect(bill.data()!['voidReason'], 'Wrong items');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the receipt can switch language without changing the app', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/bills/s1/b1');
    await settle(tester);
    expect(find.text('Toor Dal'), findsOneWidget);

    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('తెలుగు')));
    await settle(tester);
    expect(find.text('కందిపప్పు'), findsOneWidget);
    expect(harness.session.language, 'en');
  });

  testWidgets('switching store scope updates the customer list', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/customers');
    await settle(tester);
    expect(find.text('Sita'), findsNWidgets(2));

    harness.scope.select('s2');
    await settle(tester);
    expect(find.text('Sita'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner changes a staff role; a manager has no edit button', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(role: MemberRole.owner, seed: seedEverything);
    await pumpApp(tester, harness);
    go(tester, '/staff');
    await settle(tester);
    expect(find.text('ABCD2345'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Edit'));
    await settle(tester);
    await tester.tap(inDialog(find.widgetWithText(CheckboxListTile, 'Market')));
    await settle(tester);
    await tester.tap(inDialog(find.text('Save')));
    await settle(tester);
    final member = await harness.db.doc('businesses/$businessId/members/m2').get();
    expect(member.data()!['storeIds'], containsAll(<String>['s1', 's2']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a manager sees staff read-only', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(
      role: MemberRole.manager,
      storeIds: const ['s1'],
      seed: seedEverything,
    );
    await pumpApp(tester, harness);
    go(tester, '/staff');
    await settle(tester);
    expect(find.text('Only the owner can change roles and store access.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);

    go(tester, '/stores');
    await settle(tester);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Store name'), findsNothing);
  });

  testWidgets('a store-scoped manager cannot deep-link into another store', (tester) async {
    useViewport(tester, 1400, 1000);
    final harness = await buildHarness(
      role: MemberRole.manager,
      storeIds: const ['s1'],
      seed: seedEverything,
    );
    await pumpApp(tester, harness);
    go(tester, '/customers/s2/c1');
    await settle(tester);
    expect(find.text('This item is not available.'), findsOneWidget);
  });
}
