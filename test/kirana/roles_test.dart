import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/bills_screen.dart';
import 'package:upi_split/kirana/screens/expenses_screen.dart';
import 'package:upi_split/kirana/screens/product_screens.dart';
import 'package:upi_split/kirana/screens/receipt_screen.dart';
import 'package:upi_split/kirana/screens/reports_screen.dart';
import 'package:upi_split/kirana/screens/suppliers_screen.dart';

import 'support/harness.dart';

void main() {
  setUpAll(setUpStrings);

  testWidgets('a cashier sees no profit, reports or suppliers', (t) async {
    final h = await pumpApp(t, role: MemberRole.cashier);
    expect(find.text("Today's sales"), findsOneWidget);
    expect(find.byKey(const Key('home_profit')), findsNothing);
    expect(find.text('Profit'), findsNothing);

    await h.tab('More');
    expect(find.byKey(const Key('more_reports')), findsNothing);
    expect(find.byKey(const Key('more_suppliers')), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Suppliers'), findsNothing);
    expect(find.text('Staff'), findsNothing);
    expect(find.byKey(const Key('more_bills')), findsOneWidget);
  });

  testWidgets('a manager sees profit, reports and suppliers', (t) async {
    final h = await pumpApp(t, role: MemberRole.manager);
    expect(find.byKey(const Key('home_profit')), findsOneWidget);
    await h.tab('More');
    expect(find.byKey(const Key('more_reports')), findsOneWidget);
    expect(find.byKey(const Key('more_suppliers')), findsOneWidget);
  });

  testWidgets('a cashier sees no cost and no product management', (t) async {
    final h = await pumpApp(t, role: MemberRole.cashier);
    await h.tab('Stock');
    expect(find.byKey(const Key('stock_add_product')), findsNothing);
    expect(find.byKey(const Key('stock_inactive_filter')), findsNothing);

    await t.tap(find.byKey(const ValueKey('stock_soap')));
    await settle(t);
    expect(find.text('Selling price'), findsOneWidget);
    expect(find.text('Cost price'), findsNothing);
    expect(find.text('₹32 / Piece'), findsNothing);
    expect(find.byKey(const Key('product_edit')), findsNothing);
    expect(find.byKey(const Key('stock_adjust')), findsNothing);
    expect(find.byKey(const Key('product_active_toggle')), findsNothing);
  });

  testWidgets('a manager sees cost and product management', (t) async {
    final h = await pumpApp(t, role: MemberRole.manager);
    await h.open(const ProductDetailScreen(productId: 'soap'));
    expect(find.text('Cost price'), findsOneWidget);
    expect(find.text('₹32 / Piece'), findsOneWidget);
    expect(find.byKey(const Key('product_edit')), findsOneWidget);
    expect(find.byKey(const Key('stock_adjust')), findsOneWidget);
    expect(find.byKey(const Key('product_active_toggle')), findsOneWidget);
  });

  testWidgets('manager-only screens refuse a cashier who reaches them', (
    t,
  ) async {
    final h = await pumpApp(t, role: MemberRole.cashier);
    await h.open(const ReportsScreen());
    expect(find.text('This is for managers only'), findsOneWidget);
    expect(find.text('Net profit'), findsNothing);
    Navigator.of(t.element(find.byType(ReportsScreen))).pop();
    await settle(t);
    await h.open(const SuppliersScreen());
    expect(find.text('This is for managers only'), findsOneWidget);
  });

  testWidgets('a cashier cannot void a bill or an expense', (t) async {
    final h = await pumpApp(t, role: MemberRole.cashier);
    final repo = h.session.repository;
    await h.tab('Billing');
    await t.tap(find.byKey(const ValueKey('product_soap')));
    await settle(t);
    await t.tap(find.byKey(const Key('billing_checkout')));
    await settle(t);
    await t.tap(find.byKey(const Key('checkout_save')));
    await settle(t);
    expect(find.byKey(const Key('receipt_void')), findsNothing);
    await t.tap(find.byKey(const Key('receipt_new_bill')));
    await settle(t);

    await h.open(const BillsScreen());
    final billId =
        (await h.db.collection('$storePath/bills').get()).docs.single.id;
    await t.tap(find.byKey(ValueKey('bill_menu_$billId')));
    await settle(t);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Void bill'), findsNothing);
    await t.tapAt(Offset.zero);
    await settle(t);

    final expenseId = repo.addExpense(
      category: 'rent',
      amountPaise: 1000,
      method: PaymentMethod.cash,
    );
    await h.open(const ExpensesScreen());
    expect(find.byKey(ValueKey('expense_$expenseId')), findsOneWidget);
    expect(find.byKey(ValueKey('expense_void_$expenseId')), findsNothing);
  });

  testWidgets('a manager voids a bill with a required reason', (t) async {
    final h = await pumpApp(t, role: MemberRole.manager);
    await h.tab('Billing');
    await t.tap(find.byKey(const ValueKey('product_soap')));
    await settle(t);
    await t.tap(find.byKey(const Key('billing_checkout')));
    await settle(t);
    await t.tap(find.byKey(const Key('checkout_save')));
    await settle(t);

    await t.tap(find.byKey(const Key('receipt_void')));
    await settle(t);
    await t.tap(find.byKey(const Key('void_confirm')));
    await settle(t);
    expect(find.text('Required'), findsOneWidget);
    await t.enterText(find.byKey(const Key('void_reason')), 'Wrong item');
    await t.tap(find.byKey(const Key('void_confirm')));
    await settle(t);

    final bill = (await h.db.collection('$storePath/bills').get()).docs.single
        .data();
    expect(bill['voided'], true);
    expect(bill['voidReason'], 'Wrong item');
    expect((await h.doc('products/soap'))['stockMilli'], 10000);
    expect(find.byType(ReceiptView), findsOneWidget);
    expect(find.text('Void: Wrong item'), findsOneWidget);
  });
}
