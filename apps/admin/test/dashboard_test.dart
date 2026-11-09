import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_core/kirana_core.dart';

import 'test_helpers.dart';

void main() {
  Future<Harness> seededOwner({String language = 'en'}) => buildHarness(
        role: MemberRole.owner,
        language: language,
        seed: (db) async {
          await seedSales(db, 's1');
          await seedSales(db, 's2', sales: 50000, cogs: 20000);
        },
      );

  testWidgets('shows combined totals across all stores', (tester) async {
    useViewport(tester, 1400, 3000);
    final harness = await seededOwner();
    await pumpApp(tester, harness);

    expect(find.text('Dashboard'), findsWidgets);
    // Today, both stores: 1500 + 500 sales, gross 2000 - 1100, net 900 - 160.
    expect(find.text('₹2,000'), findsWidgets);
    expect(find.text('₹900'), findsWidgets);
    expect(find.text('₹740'), findsWidgets);
    // Outstanding across stores: 450 + 450; low stock in each store.
    expect(find.text('Total outstanding'), findsOneWidget);
    expect(find.text('₹900'), findsWidgets);
    expect(find.text('Sales by store, this month'), findsOneWidget);
    expect(find.text('Top products, this month'), findsOneWidget);
    expect(find.text('Sita'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single store selection hides the per-store chart', (tester) async {
    useViewport(tester, 1400, 3000);
    final harness = await seededOwner();
    harness.scope.select('s1');
    await pumpApp(tester, harness);

    expect(find.text('Sales by store, this month'), findsNothing);
    expect(find.text('₹1,500'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'te']) {
    testWidgets('lays out at 360px in $language without overflow', (tester) async {
      useViewport(tester, 360, 800);
      final harness = await seededOwner(language: language);
      await pumpApp(tester, harness);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty business shows empty states, not errors', (tester) async {
    useViewport(tester, 1200, 3000);
    final harness = await buildHarness(role: MemberRole.owner);
    await pumpApp(tester, harness);

    expect(find.text('No dues to collect'), findsOneWidget);
    expect(find.text('Stock levels are fine'), findsOneWidget);
    expect(find.text('No sales in this period'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
