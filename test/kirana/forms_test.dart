import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/expenses_screen.dart';
import 'package:upi_split/kirana/screens/product_screens.dart';
import 'package:upi_split/kirana/screens/settings_screen.dart';
import 'package:upi_split/kirana/screens/suppliers_screen.dart';

import 'support/harness.dart';

void main() {
  setUpAll(setUpStrings);

  Future<void> tapKey(WidgetTester t, Key key) async {
    await t.ensureVisible(find.byKey(key));
    await t.pump();
    await t.tap(find.byKey(key));
    await settle(t);
  }

  const small = Size(360, 640);

  testWidgets(
    'a product needs a name and price, then saves with opening stock',
    (t) async {
      final h = await pumpApp(t, size: small);
      await h.open(const ProductFormScreen());

      await tapKey(t, const Key('product_save'));
      expect(find.text('Required'), findsNWidgets(2));

      await t.enterText(find.byKey(const Key('product_name')), 'Sugar');
      await t.enterText(
        find.byKey(const Key('product_barcode')),
        '8901000000028',
      );
      await t.enterText(find.byKey(const Key('product_price')), '45.50');
      await t.enterText(find.byKey(const Key('product_cost')), '40');
      await t.enterText(find.byKey(const Key('product_opening')), '12.5');
      await tapKey(t, const Key('product_save'));
      expect(
        find.text('Another product already has this barcode'),
        findsOneWidget,
      );

      await t.enterText(find.byKey(const Key('product_barcode')), '');
      await tapKey(t, const Key('product_save'));
      final products = await h.collection('products');
      final sugar = products.singleWhere((p) => p['name'] == 'Sugar');
      expect(sugar['pricePaise'], 4550);
      expect(sugar['costPaise'], 4000);
      expect(sugar['stockMilli'], 12500);
      expect((await h.collection('stockMoves')).single['note'], 'opening');
    },
  );

  testWidgets('a stock adjustment needs a reason and moves stock', (t) async {
    final h = await pumpApp(t, size: small);
    await h.open(const ProductDetailScreen(productId: 'soap'));
    await tapKey(t, const Key('stock_adjust'));
    await t.enterText(find.byKey(const Key('adjust_qty')), '2');
    await tapKey(t, const Key('adjust_save'));
    expect(find.text('Choose or type a reason'), findsOneWidget);
    expect((await h.doc('products/soap'))['stockMilli'], 10000);

    await t.tap(find.text('Remove stock'));
    await settle(t);
    await t.tap(find.text('Damaged'));
    await settle(t);
    await tapKey(t, const Key('adjust_save'));
    expect((await h.doc('products/soap'))['stockMilli'], 8000);
    final move = (await h.collection('stockMoves')).single;
    expect(move['deltaMilli'], -2000);
    expect(move['note'], 'Damaged');
  });

  testWidgets('deactivating asks first and the product can come back', (
    t,
  ) async {
    final h = await pumpApp(t, size: small);
    await h.open(const ProductDetailScreen(productId: 'soap'));
    await tapKey(t, const Key('product_active_toggle'));
    await t.tap(find.widgetWithText(FilledButton, 'Stop selling'));
    await settle(t);
    expect((await h.doc('products/soap'))['active'], false);
    await tapKey(t, const Key('product_active_toggle'));
    expect((await h.doc('products/soap'))['active'], true);
  });

  testWidgets(
    'a supplier purchase brings stock in and leaves the rest on account',
    (t) async {
      final h = await pumpApp(t, size: small);
      await h.open(const SupplierDetailScreen(supplierId: 'v1'));
      await tapKey(t, const Key('supplier_purchase'));

      await tapKey(t, const Key('purchase_save'));
      expect(find.text('Required'), findsOneWidget);

      await tapKey(t, const Key('purchase_add_line'));
      await t.tap(find.byKey(const ValueKey('stockin_product_soap')));
      await settle(t);
      await t.enterText(find.byKey(const Key('stockin_qty')), '10');
      await t.enterText(find.byKey(const Key('stockin_cost')), '30');
      await tapKey(t, const Key('stockin_done'));

      final amount = t.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('purchase_amount')),
          matching: find.byType(EditableText),
        ),
      );
      expect(amount.controller.text, '300', reason: 'Amount follows the lines');

      await t.enterText(find.byKey(const Key('purchase_paid')), '500');
      await tapKey(t, const Key('purchase_save'));
      expect(find.text('Paid is more than the bill amount'), findsOneWidget);

      await t.enterText(find.byKey(const Key('purchase_paid')), '100');
      await tapKey(t, const Key('purchase_save'));
      final soap = await h.doc('products/soap');
      expect(soap['stockMilli'], 20000);
      expect(soap['costPaise'], 3000);
      expect((await h.doc('suppliers/v1'))['balancePaise'], 500000 + 20000);
      expect((await h.collection('supplierTxns')).length, 2);
    },
  );

  testWidgets(
    'expenses take a chip or custom category, and managers can void',
    (t) async {
      final h = await pumpApp(t, size: small);
      await h.open(const ExpensesScreen());
      await tapKey(t, const Key('expense_add'));
      await t.enterText(find.byKey(const Key('expense_amount')), '250');
      await tapKey(t, const Key('expense_save'));
      expect(find.text('Choose a category'), findsOneWidget);

      await tapKey(t, const Key('expense_cat_custom'));
      await t.enterText(find.byKey(const Key('expense_custom')), 'Tea');
      await tapKey(t, const Key('expense_save'));
      expect(find.text('Tea'), findsOneWidget);
      final key = dayKey(DateTime.now());
      expect((await h.doc('days/$key'))['expensePaise'], 25000);

      final id =
          (await h.db.collection('$storePath/expenses').get()).docs.single.id;
      await tapKey(t, ValueKey('expense_void_$id'));
      await t.tap(find.widgetWithText(FilledButton, 'Void expense'));
      await settle(t);
      expect((await h.doc('expenses/$id'))['voided'], true);
      expect((await h.doc('days/$key'))['expensePaise'], 0);
    },
  );

  testWidgets('the owner edits store details without waiting on the server', (
    t,
  ) async {
    final h = await pumpApp(t, size: small);
    await h.open(StoreDetailsScreen(store: h.session.store!));
    await t.enterText(find.byKey(const Key('store_upi')), 'not an id');
    await tapKey(t, const Key('store_save'));
    expect(find.text('That UPI ID does not look right'), findsOneWidget);

    await t.enterText(find.byKey(const Key('store_upi')), 'shop.name@okaxis');
    await t.enterText(find.byKey(const Key('store_footer')), 'Visit again');
    await tapKey(t, const Key('store_save'));
    expect(find.byType(StoreDetailsScreen), findsNothing);
    final store = (await h.db.doc(storePath).get()).data()!;
    expect(store['upiId'], 'shop.name@okaxis');
    expect(store['receiptFooter'], 'Visit again');
    expect(store['name'], 'Lakshmi Kirana');
  });

  testWidgets('store details are offered to the owner only', (t) async {
    final owner = await pumpApp(t, size: small);
    await owner.open(const SettingsScreen());
    expect(find.byKey(const Key('edit_store')), findsOneWidget);
    expect(find.byKey(const Key('language_toggle')), findsOneWidget);
  });

  testWidgets('a manager cannot edit store details', (t) async {
    final manager = await pumpApp(t, size: small, role: MemberRole.manager);
    await manager.open(const SettingsScreen());
    expect(find.byKey(const Key('edit_store')), findsNothing);
  });
}
