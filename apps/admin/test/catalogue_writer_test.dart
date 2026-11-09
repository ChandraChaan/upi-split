import 'package:flutter_test/flutter_test.dart';
import 'package:kirana_admin/data/catalogue_writer.dart';
import 'package:kirana_core/kirana_core.dart';

import 'test_helpers.dart';

void main() {
  const actor = Actor(uid: 'u1', name: 'Ravi', role: MemberRole.manager);

  test('writes products and opening stock in several batches', () async {
    final db = TestFirestore();
    final repo = StoreRepository(db, businessId: 'b1', storeId: 's1', actor: actor);
    final lines = List.generate(
      200,
      (i) => CatalogueLine(
        Product(id: '', name: 'Item $i', pricePaise: 1000),
        openingStockMilli: 2500,
      ),
    );

    final batches = CatalogueWriter(repo).write(lines, label: 'importProducts');
    await Future<void>.delayed(Duration.zero);

    expect(batches, 3);
    final products = await repo.products().first;
    expect(products.length, 200);
    expect(products.every((p) => p.stockMilli == 2500), isTrue);
    final moves = await db.collection('businesses/b1/stores/s1/stockMoves').get();
    expect(moves.docs.length, 200);
    final move = moves.docs.first.data();
    expect(move['reason'], 'adjustment');
    expect(move['byUid'], 'u1');
    expect(move['deltaMilli'], 2500);
  });

  test('an update keeps the existing stock and writes no movement', () async {
    final db = TestFirestore();
    final repo = StoreRepository(db, businessId: 'b1', storeId: 's1', actor: actor);
    await db.doc('businesses/b1/stores/s1/products/p1').set({'name': 'Soap', 'stockMilli': 7000});

    CatalogueWriter(repo).write(
      [const CatalogueLine(Product(id: 'p1', name: 'Soap', pricePaise: 4500))],
      label: 'importProducts',
    );
    await Future<void>.delayed(Duration.zero);

    final product = (await repo.products().first).single;
    expect(product.pricePaise, 4500);
    expect(product.stockMilli, 7000);
    final moves = await db.collection('businesses/b1/stores/s1/stockMoves').get();
    expect(moves.docs, isEmpty);
  });
}
