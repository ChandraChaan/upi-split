import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:upi_split/kirana/screens/bills_screen.dart';
import 'package:upi_split/kirana/screens/checkout_screen.dart';
import 'package:upi_split/kirana/screens/customer_detail_screen.dart';
import 'package:upi_split/kirana/screens/customer_form_screen.dart';
import 'package:upi_split/kirana/screens/expenses_screen.dart';
import 'package:upi_split/kirana/screens/market_purchase_screen.dart';
import 'package:upi_split/kirana/screens/product_screens.dart';
import 'package:upi_split/kirana/screens/receipt_screen.dart';
import 'package:upi_split/kirana/screens/reminders_screen.dart';
import 'package:upi_split/kirana/screens/reports_screen.dart';
import 'package:upi_split/kirana/screens/settings_screen.dart';
import 'package:upi_split/kirana/screens/stock_screen.dart';
import 'package:upi_split/kirana/screens/suppliers_screen.dart';

import 'package:upi_split/kirana/widgets/common.dart';

import 'support/harness.dart';

Bill sampleBill() => Bill(
  id: 'x1',
  number: '261109-AB-1',
  items: const [
    BillItem(
      name: 'A very long product name that wraps',
      nameTe: 'చాలా పొడవైన సరుకు పేరు ఇది రెండు లైన్లు వస్తుంది',
      unit: Unit.kg,
      qtyMilli: 1250,
      pricePaise: 123456,
      costPaise: 100000,
      totalPaise: 154320,
      productId: 'rice',
    ),
  ],
  subtotalPaise: 154320,
  discountPaise: 320,
  totalPaise: 154000,
  cashPaise: 100000,
  upiPaise: 4000,
  creditPaise: 50000,
  at: DateTime(2026, 11, 9, 18, 30),
  dayKey: '2026-11-09',
  byUid: 'u1',
  byName: 'Ravi',
  customerId: 'c1',
  customerName: 'Suresh',
  customerPhone: '9876500001',
);

Cart sampleCart() {
  final cart = Cart();
  cart.addProduct(
    const Product(
      id: 'rice',
      name: 'A very long product name that wraps',
      nameTe: 'చాలా పొడవైన సరుకు పేరు ఇది రెండు లైన్లు వస్తుంది',
      unit: Unit.kg,
      pricePaise: 123456,
    ),
    1250,
  );
  cart.addCustom('Bag', 1000);
  return cart;
}

/// A rendering overflow fails these tests. The test font draws every glyph a
/// full em wide, which is a harsher width check than real Telugu text.
void main() {
  setUpAll(setUpStrings);

  final screens = <String, Widget Function()>{
    'checkout': () => CheckoutScreen(cart: sampleCart()),
    'receipt': () => ReceiptScreen(bill: sampleBill(), justSaved: true),
    'bills': () => const BillsScreen(),
    'customer detail': () => const CustomerDetailScreen(customerId: 'c1'),
    'customer form': () => const CustomerFormScreen(),
    'reminders': () => const RemindersScreen(),
    'product detail': () => const ProductDetailScreen(productId: 'salt'),
    'product form': () => const ProductFormScreen(),
    'suppliers': () => const SuppliersScreen(),
    'supplier detail': () => const SupplierDetailScreen(supplierId: 'v1'),
    'supplier form': () => const SupplierFormScreen(),
    'purchase': () => const PurchaseScreen(
      supplier: Supplier(
        id: 'v1',
        name: 'Sri Venkateswara Agencies',
        balancePaise: 500000,
      ),
    ),
    'expenses': () => const ExpensesScreen(),
    'purchases': () => const PurchasesScreen(),
    'wholesale purchase': () => const MarketPurchaseScreen(),
    'stock': () => const StockScreen(),
    'expense add': () => const ExpensesScreen(openAdd: true),
    'reports': () => const ReportsScreen(),
    'settings': () => const SettingsScreen(),
    'store details': () => const StoreDetailsScreen(
      store: Store(id: 's1', name: 'Lakshmi Kirana'),
    ),
  };

  for (final language in ['te', 'en']) {
    group('$language at phone width', () {
      testWidgets('tabs', (t) async {
        final h = await pumpApp(
          t,
          language: language,
          size: const Size(360, 640),
        );
        final labels = language == 'te'
            ? ['అమ్మకం', 'ఖాతా', 'ఈరోజు', 'ఇంకా']
            : ['Sell', 'Khata', 'Today', 'More'];
        for (final label in labels) {
          await h.tab(label);
          expect(find.byType(ErrorState), findsNothing);
        }
      });

      testWidgets('signed out', (t) async {
        await pumpApp(
          t,
          language: language,
          size: const Size(360, 640),
          signedIn: false,
        );
        expect(find.byKey(const Key('language_toggle')), findsOneWidget);
      });

      Future<void> sheet(
        WidgetTester t,
        Harness h,
        Widget screen,
        String key,
      ) async {
        await h.open(screen);
        await t.ensureVisible(find.byKey(Key(key)));
        await t.pump();
        await t.tap(find.byKey(Key(key)));
        await settle(t);
        expect(find.byType(BottomSheet), findsOneWidget);
      }

      const size = Size(360, 640);
      const customer = CustomerDetailScreen(customerId: 'c1');
      const product = ProductDetailScreen(productId: 'soap');
      const supplier = SupplierDetailScreen(supplierId: 'v1');
      for (final (name, screen, key) in [
        ('payment sheet', customer, 'record_payment'),
        ('credit sheet', customer, 'record_credit'),
        ('adjustment sheet', customer, 'khata_adjust'),
        ('stock adjust sheet', product, 'stock_adjust'),
        ('supplier payment sheet', supplier, 'supplier_payment'),
        ('void sheet', ReceiptScreen(bill: sampleBill()), 'receipt_void'),
        (
          'customer picker',
          CheckoutScreen(cart: sampleCart()),
          'checkout_customer',
        ),
      ]) {
        testWidgets(name, (t) async {
          final h = await pumpApp(t, language: language, size: size);
          await sheet(t, h, screen, key);
        });
      }

      testWidgets('billing sheets and split payment', (t) async {
        final h = await pumpApp(t, language: language, size: size);
        await h.tab(language == 'te' ? 'అమ్మకం' : 'Sell');
        await t.tap(find.byKey(const Key('sell_items')));
        await settle(t);
        await t.tap(find.byKey(const Key('add_custom_line')));
        await settle(t);
        expect(find.byType(BottomSheet), findsOneWidget);
        Navigator.of(t.element(find.byType(BottomSheet))).pop();
        await settle(t);

        await t.tap(find.byKey(const ValueKey('product_rice')));
        await settle(t);
        expect(find.byType(BottomSheet), findsOneWidget);
        Navigator.of(t.element(find.byType(BottomSheet))).pop();
        await settle(t);

        await t.tap(find.byKey(const ValueKey('product_soap')));
        await settle(t);
        await t.tap(find.byKey(const Key('billing_checkout')));
        await settle(t);
        await t.ensureVisible(find.byKey(const Key('pay_split')));
        await t.pump();
        await t.tap(find.byKey(const Key('pay_split')));
        await settle(t);
        expect(find.byKey(const Key('split_credit')), findsOneWidget);
      });

      screens.forEach((name, build) {
        testWidgets(name, (t) async {
          final h = await pumpApp(
            t,
            language: language,
            size: const Size(360, 640),
          );
          await h.open(build());
          expect(find.byType(ErrorState), findsNothing);
          expect(find.byType(LoadingState), findsNothing);
        });
      });
    });
  }
}
