import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kirana_core/kirana_core.dart';

/// A product to write, with the stock to open it with.
class CatalogueLine {
  const CatalogueLine(this.product, {this.openingStockMilli = 0});
  final Product product;
  final int openingStockMilli;

  /// Writes this line uses in a batch, with a server-side field transform
  /// counted as a write of its own, which Firestore's limit has done.
  int get writeCost => openingStockMilli == 0 ? 2 : 5;
}

/// Firestore's limit is 500 writes per batch; this leaves headroom.
const int maxWritesPerBatch = 450;

/// Splits [items] into runs whose total cost stays within [maxWrites].
List<List<T>> splitByWrites<T>(
  Iterable<T> items,
  int Function(T item) cost, {
  int maxWrites = maxWritesPerBatch,
}) {
  final chunks = <List<T>>[];
  var current = <T>[];
  var used = 0;
  for (final item in items) {
    final c = cost(item);
    if (current.isNotEmpty && used + c > maxWrites) {
      chunks.add(current);
      current = <T>[];
      used = 0;
    }
    current.add(item);
    used += c;
  }
  if (current.isNotEmpty) chunks.add(current);
  return chunks;
}

/// Bulk product writes for CSV import and catalogue copy.
///
/// StoreRepository.saveProduct commits one batch per product, and every commit
/// re-fires the live product listeners, which is too slow for thousands of rows.
/// The documents written here match saveProduct field for field.
class CatalogueWriter {
  CatalogueWriter(this.repo);
  final StoreRepository repo;

  /// Queues all lines without waiting for the server. Returns the batch count.
  int write(List<CatalogueLine> lines, {required String label}) {
    final chunks = splitByWrites(lines, (CatalogueLine l) => l.writeCost);
    for (final chunk in chunks) {
      final batch = repo.db.batch();
      for (final line in chunk) {
        _add(batch, line);
      }
      final monitor = repo.sync;
      if (monitor != null) {
        monitor.track(label, batch.commit);
      } else {
        batch.commit();
      }
    }
    return chunks.length;
  }

  void _add(WriteBatch batch, CatalogueLine line) {
    final product = line.product;
    final products = repo.storeRef.collection('products');
    final ref = product.id.isEmpty ? products.doc() : products.doc(product.id);
    final stamp = {'updatedAt': FieldValue.serverTimestamp()};
    batch.set(
      ref,
      {
        ...product.toMap(),
        if (product.id.isEmpty) 'stockMilli': 0,
        ...stamp,
      },
      SetOptions(merge: true),
    );
    if (line.openingStockMilli == 0) return;
    batch.set(
      ref,
      {'stockMilli': FieldValue.increment(line.openingStockMilli), ...stamp},
      SetOptions(merge: true),
    );
    batch.set(repo.storeRef.collection('stockMoves').doc(), {
      'productId': ref.id,
      'deltaMilli': line.openingStockMilli,
      'reason': StockReason.adjustment.name,
      'refId': null,
      'note': 'opening',
      'at': Timestamp.fromDate(DateTime.now()),
      'byUid': repo.actor.uid,
      'byName': repo.actor.name,
    });
  }
}

/// Every product in the store, active or not, from the server when reachable.
/// A live query's first result can be a partial local cache, which would make
/// products already in the store look missing and get copied a second time.
Future<List<Product>> fetchAllProducts(StoreRepository repo) async {
  final snapshot = await repo.storeRef.collection('products').get();
  return snapshot.docs.map((d) => Product.fromMap(d.id, d.data())).toList();
}

/// Products from [source] that [target] does not already have, matched on
/// barcode and then on name. Copies start with no stock in the new store.
List<Product> productsToCopy(List<Product> source, List<Product> target) {
  final barcodes = {for (final p in target) if (p.barcode.isNotEmpty) p.barcode};
  final names = {for (final p in target) p.name.trim().toLowerCase()};
  return [
    for (final p in source)
      if (p.active &&
          !(p.barcode.isNotEmpty && barcodes.contains(p.barcode)) &&
          !names.contains(p.name.trim().toLowerCase()))
        Product(
          id: '',
          name: p.name,
          nameTe: p.nameTe,
          barcode: p.barcode,
          category: p.category,
          unit: p.unit,
          pricePaise: p.pricePaise,
          costPaise: p.costPaise,
          lowStockMilli: p.lowStockMilli,
        ),
  ];
}
