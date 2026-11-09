import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/cart.dart';
import '../domain/models.dart';
import '../domain/money.dart';
import 'sync_monitor.dart';

class StockInLine {
  const StockInLine({required this.product, required this.qtyMilli, required this.costPaise});
  final Product product;
  final int qtyMilli;

  /// Purchase cost per whole unit; becomes the product's new cost price.
  final int costPaise;
}

class InvalidOperation implements Exception {
  const InvalidOperation(this.code);
  final String code;
  @override
  String toString() => 'InvalidOperation($code)';
}

/// All reads and writes for one store.
///
/// Offline rules this class enforces:
///  * No transactions, because they fail without a network. Multi-document
///    changes are write batches, which queue and apply atomically on the server.
///  * Balances, stock and daily totals change only by FieldValue.increment, so
///    concurrent offline devices merge rather than overwrite each other.
///  * Document ids are generated on the device, so a retry cannot duplicate.
///  * Ledgers are append-only; a mistake is corrected by a reversing entry.
class StoreRepository {
  StoreRepository(
    this.db, {
    required this.businessId,
    required this.storeId,
    required this.actor,
    this.sync,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final FirebaseFirestore db;
  final String businessId;
  final String storeId;
  final Actor actor;
  final SyncMonitor? sync;
  final DateTime Function() _clock;

  DocumentReference<Json> get storeRef =>
      db.doc('businesses/$businessId/stores/$storeId');
  CollectionReference<Json> _c(String name) => storeRef.collection(name);

  // ---------------------------------------------------------------- reads

  Stream<List<Customer>> customers() => _c('customers').snapshots().map((s) =>
      s.docs.map((d) => Customer.fromMap(d.id, d.data())).where((c) => !c.archived).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<Customer?> customer(String id) => _c('customers').doc(id).snapshots().map(
      (d) => d.exists ? Customer.fromMap(d.id, d.data()!) : null);

  Stream<List<KhataEntry>> khata(String customerId, {int limit = 200}) => _c('khata')
      .where('customerId', isEqualTo: customerId)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => KhataEntry.fromMap(d.id, d.data())).toList());

  Stream<List<Product>> products({bool includeInactive = false}) =>
      _c('products').snapshots().map((s) => s.docs
          .map((d) => Product.fromMap(d.id, d.data()))
          .where((p) => includeInactive || p.active)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<List<StockMove>> stockMoves(String productId, {int limit = 100}) => _c('stockMoves')
      .where('productId', isEqualTo: productId)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => StockMove.fromMap(d.id, d.data())).toList());

  Stream<List<Bill>> bills({required DateTime from, required DateTime to, int limit = 500}) =>
      _c('bills')
          .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('at', isLessThan: Timestamp.fromDate(to))
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map((d) => Bill.fromMap(d.id, d.data())).toList());

  Stream<Bill?> bill(String id) => _c('bills')
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? Bill.fromMap(d.id, d.data()!) : null);

  Stream<List<Expense>> expenses({required DateTime from, required DateTime to}) => _c('expenses')
      .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('at', isLessThan: Timestamp.fromDate(to))
      .orderBy('at', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Expense.fromMap(d.id, d.data())).toList());

  Stream<List<Supplier>> suppliers() => _c('suppliers').snapshots().map((s) =>
      s.docs.map((d) => Supplier.fromMap(d.id, d.data())).where((x) => !x.archived).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Stream<List<SupplierTxn>> supplierTxns(String supplierId, {int limit = 200}) =>
      _c('supplierTxns')
          .where('supplierId', isEqualTo: supplierId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map((d) => SupplierTxn.fromMap(d.id, d.data())).toList());

  /// Rollups for the inclusive day-key range.
  Stream<List<DayRollup>> days({required String from, required String to}) => _c('days')
      .where(FieldPath.documentId, isGreaterThanOrEqualTo: from)
      .where(FieldPath.documentId, isLessThanOrEqualTo: to)
      .snapshots()
      .map((s) => s.docs.map((d) => DayRollup.fromMap(d.id, d.data())).toList());

  Stream<DayRollup> day(String key) => _c('days').doc(key).snapshots().map(
      (d) => d.exists ? DayRollup.fromMap(d.id, d.data()!) : DayRollup(dayKey: key));

  // ------------------------------------------------------------ customers

  /// Creates when [id] is null. Never touches the balance.
  String saveCustomer({
    String? id,
    required String name,
    String phone = '',
    String address = '',
    int creditLimitPaise = 0,
  }) {
    if (name.trim().isEmpty) throw const InvalidOperation('name_required');
    final ref = id == null ? _c('customers').doc() : _c('customers').doc(id);
    final batch = db.batch();
    batch.set(
      ref,
      {
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'creditLimitPaise': creditLimitPaise,
        if (id == null) ...{'balancePaise': 0, 'archived': false},
        ..._stamp(),
      },
      SetOptions(merge: true),
    );
    _commit('saveCustomer', batch);
    return ref.id;
  }

  void archiveCustomer(String id) {
    _requireManager();
    final batch = db.batch()
      ..set(_c('customers').doc(id), {'archived': true, ..._stamp()}, SetOptions(merge: true));
    _commit('archiveCustomer', batch);
  }

  void setDueDate(String customerId, DateTime? due) {
    final batch = db.batch()
      ..set(
        _c('customers').doc(customerId),
        {'dueDate': due == null ? null : Timestamp.fromDate(due), ..._stamp()},
        SetOptions(merge: true),
      );
    _commit('setDueDate', batch);
  }

  /// A purchase written straight into the khata, without an itemised bill.
  String recordKhataPurchase({
    required String customerId,
    required int amountPaise,
    String note = '',
  }) {
    if (amountPaise <= 0) throw const InvalidOperation('amount_required');
    final batch = db.batch();
    final id = _addKhata(batch,
        customerId: customerId,
        kind: KhataKind.purchase,
        signedPaise: amountPaise,
        method: PaymentMethod.credit,
        note: note);
    _commit('recordKhataPurchase', batch);
    return id;
  }

  /// A payment received against dues. May exceed dues, which leaves an advance.
  String recordPayment({
    required String customerId,
    required int amountPaise,
    required PaymentMethod method,
    String note = '',
    bool clearDueDate = false,
  }) {
    if (amountPaise <= 0) throw const InvalidOperation('amount_required');
    if (method == PaymentMethod.credit) throw const InvalidOperation('invalid_method');
    final batch = db.batch();
    final id = _addKhata(batch,
        customerId: customerId,
        kind: KhataKind.payment,
        signedPaise: -amountPaise,
        method: method,
        note: note,
        customerExtra: clearDueDate ? const {'dueDate': null} : const {});
    _roll(batch, dayKey(_clock()), {
      method == PaymentMethod.cash ? 'collectionCashPaise' : 'collectionUpiPaise': amountPaise,
    });
    _commit('recordPayment', batch);
    return id;
  }

  /// A correction with no money moving. Positive adds to dues.
  String recordAdjustment({
    required String customerId,
    required int signedPaise,
    required String note,
  }) {
    if (signedPaise == 0) throw const InvalidOperation('amount_required');
    _requireManager();
    final batch = db.batch();
    final id = _addKhata(batch,
        customerId: customerId,
        kind: KhataKind.adjustment,
        signedPaise: signedPaise,
        note: note);
    _commit('recordAdjustment', batch);
    return id;
  }

  /// Undoes a khata entry. The reversal's id derives from the original, so the
  /// server rejects a second reversal even from another offline device.
  void reverseKhataEntry(KhataEntry entry, {String note = ''}) {
    _requireManager();
    if (entry.reversesId != null) throw const InvalidOperation('cannot_reverse_reversal');
    if (entry.billId != null) throw const InvalidOperation('void_the_bill_instead');
    final batch = db.batch();
    _addKhata(batch,
        id: 'rev_${entry.id}',
        customerId: entry.customerId,
        kind: entry.kind,
        signedPaise: -entry.amountPaise,
        method: entry.method,
        note: note,
        reversesId: entry.id);
    if (entry.kind == KhataKind.payment && entry.method != null) {
      _roll(batch, dayKey(entry.at), {
        entry.method == PaymentMethod.cash ? 'collectionCashPaise' : 'collectionUpiPaise':
            entry.amountPaise,
      });
    }
    _commit('reverseKhataEntry', batch);
  }

  void logReminder({required Customer customer, required String channel}) {
    final batch = db.batch();
    final now = _clock();
    batch.set(_c('reminders').doc(), {
      'customerId': customer.id,
      'channel': channel,
      'amountPaise': customer.balancePaise,
      'at': Timestamp.fromDate(now),
      'byUid': actor.uid,
      'byName': actor.name,
    });
    batch.set(
      _c('customers').doc(customer.id),
      {'lastReminderAt': Timestamp.fromDate(now), ..._stamp()},
      SetOptions(merge: true),
    );
    _commit('logReminder', batch);
  }

  /// Rebuilds a stored balance from the ledger. Run online only, when no other
  /// device has writes waiting, or it can overwrite their increments.
  Future<int> recalculateCustomerBalance(String customerId) async {
    _requireManager();
    final docs = await _c('khata')
        .where('customerId', isEqualTo: customerId)
        .get(const GetOptions(source: Source.server));
    final balance = docs.docs
        .fold<int>(0, (total, d) => total + ((d.data()['amountPaise'] as num?)?.toInt() ?? 0));
    await _c('customers').doc(customerId).set(
      {'balancePaise': balance, ..._stamp()},
      SetOptions(merge: true),
    );
    return balance;
  }

  // ------------------------------------------------------------- products

  String saveProduct(Product product, {int? openingStockMilli}) {
    _requireManager();
    if (product.name.trim().isEmpty) throw const InvalidOperation('name_required');
    final ref = product.id.isEmpty ? _c('products').doc() : _c('products').doc(product.id);
    final batch = db.batch();
    batch.set(
      ref,
      {
        ...product.toMap(),
        if (product.id.isEmpty) 'stockMilli': 0,
        ..._stamp(),
      },
      SetOptions(merge: true),
    );
    if (openingStockMilli != null && openingStockMilli != 0) {
      _moveStock(batch, ref.id, openingStockMilli, StockReason.adjustment, note: 'opening');
    }
    _commit('saveProduct', batch);
    return ref.id;
  }

  void setProductActive(String productId, bool active) {
    _requireManager();
    final batch = db.batch()
      ..set(_c('products').doc(productId), {'active': active, ..._stamp()}, SetOptions(merge: true));
    _commit('setProductActive', batch);
  }

  void adjustStock({required String productId, required int deltaMilli, String note = ''}) {
    _requireManager();
    if (deltaMilli == 0) throw const InvalidOperation('quantity_required');
    final batch = db.batch();
    _moveStock(batch, productId, deltaMilli, StockReason.adjustment, note: note);
    _commit('adjustStock', batch);
  }

  // -------------------------------------------------------------- billing

  /// Records a sale. Returns the [Bill] at once so the receipt can be shown
  /// while offline. Stock may go negative when devices sell the same item
  /// offline; that is surfaced in inventory rather than blocking the sale.
  Bill createBill({
    required Cart cart,
    required PaymentSplit payment,
    required String number,
    Customer? customer,
  }) {
    final error = cart.validate(payment, customer: customer);
    if (error != null) throw InvalidOperation(error.name);

    final now = _clock();
    final key = dayKey(now);
    final ref = _c('bills').doc();
    final items = cart.lines.map((l) => l.toBillItem()).toList();
    final bill = Bill(
      id: ref.id,
      number: number,
      items: items,
      subtotalPaise: cart.subtotalPaise,
      discountPaise: cart.discountPaise,
      totalPaise: cart.totalPaise,
      cashPaise: payment.cashPaise,
      upiPaise: payment.upiPaise,
      creditPaise: payment.creditPaise,
      at: now,
      dayKey: key,
      byUid: actor.uid,
      byName: actor.name,
      customerId: customer?.id,
      customerName: customer?.name ?? '',
      customerPhone: customer?.phone ?? '',
    );

    final batch = db.batch();
    batch.set(ref, {
      'number': number,
      'items': items.map((i) => i.toMap()).toList(),
      'subtotalPaise': bill.subtotalPaise,
      'discountPaise': bill.discountPaise,
      'totalPaise': bill.totalPaise,
      'cashPaise': bill.cashPaise,
      'upiPaise': bill.upiPaise,
      'creditPaise': bill.creditPaise,
      'at': Timestamp.fromDate(now),
      'dayKey': key,
      'byUid': actor.uid,
      'byName': actor.name,
      'customerId': customer?.id,
      'customerName': bill.customerName,
      'customerPhone': bill.customerPhone,
      'voided': false,
      'voidReason': '',
      'createdAt': FieldValue.serverTimestamp(),
    });

    for (final item in items) {
      if (item.productId == null) continue;
      _moveStock(batch, item.productId!, -item.qtyMilli, StockReason.sale, refId: ref.id);
    }
    if (payment.creditPaise > 0) {
      _addKhata(batch,
          customerId: customer!.id,
          kind: KhataKind.purchase,
          signedPaise: payment.creditPaise,
          method: PaymentMethod.credit,
          billId: ref.id,
          note: number);
    }
    _roll(batch, key, _billDeltas(bill, 1), items: _itemDeltas(items, 1));
    _commit('createBill', batch);
    return bill;
  }

  /// Cancels a bill: restores stock, reverses any credit, and takes it out of
  /// the totals of the day it was sold.
  void voidBill(Bill bill, {required String reason}) {
    _requireManager();
    if (bill.voided) throw const InvalidOperation('already_voided');
    if (reason.trim().isEmpty) throw const InvalidOperation('reason_required');
    final batch = db.batch();
    batch.update(_c('bills').doc(bill.id), {
      'voided': true,
      'voidReason': reason.trim(),
      'voidedBy': actor.uid,
      'voidedAt': FieldValue.serverTimestamp(),
    });
    for (final item in bill.items) {
      if (item.productId == null) continue;
      _moveStock(batch, item.productId!, item.qtyMilli, StockReason.voidSale, refId: bill.id);
    }
    if (bill.creditPaise > 0 && bill.customerId != null) {
      _addKhata(batch,
          id: 'void_${bill.id}',
          customerId: bill.customerId!,
          kind: KhataKind.adjustment,
          signedPaise: -bill.creditPaise,
          billId: bill.id,
          note: reason.trim());
    }
    _roll(batch, bill.dayKey, _billDeltas(bill, -1), items: _itemDeltas(bill.items, -1));
    _commit('voidBill', batch);
  }

  Map<String, int> _billDeltas(Bill b, int sign) => {
        'salesPaise': sign * b.totalPaise,
        'discountPaise': sign * b.discountPaise,
        'billCount': sign,
        'cogsPaise': sign * b.cogsPaise,
        'cashSalesPaise': sign * b.cashPaise,
        'upiSalesPaise': sign * b.upiPaise,
        'creditSalesPaise': sign * b.creditPaise,
      };

  Map<String, Map<String, int>> _itemDeltas(List<BillItem> items, int sign) {
    final out = <String, Map<String, int>>{};
    for (final i in items) {
      if (i.productId == null) continue;
      final t = out.putIfAbsent(i.productId!, () => {'q': 0, 'r': 0, 'c': 0});
      t['q'] = t['q']! + sign * i.qtyMilli;
      t['r'] = t['r']! + sign * i.totalPaise;
      t['c'] = t['c']! + sign * i.cogsPaise;
    }
    return out;
  }

  // ------------------------------------------------------------- expenses

  String addExpense({
    required String category,
    required int amountPaise,
    required PaymentMethod method,
    String note = '',
    DateTime? at,
  }) {
    if (amountPaise <= 0) throw const InvalidOperation('amount_required');
    if (method == PaymentMethod.credit) throw const InvalidOperation('invalid_method');
    if (category.trim().isEmpty) throw const InvalidOperation('category_required');
    final when = at ?? _clock();
    final key = dayKey(when);
    final ref = _c('expenses').doc();
    final batch = db.batch();
    batch.set(ref, {
      'category': category.trim(),
      'amountPaise': amountPaise,
      'method': method.name,
      'note': note.trim(),
      'at': Timestamp.fromDate(when),
      'dayKey': key,
      'byUid': actor.uid,
      'byName': actor.name,
      'voided': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _roll(batch, key, _expenseDeltas(amountPaise, method, 1));
    _commit('addExpense', batch);
    return ref.id;
  }

  void voidExpense(Expense expense) {
    _requireManager();
    if (expense.voided) throw const InvalidOperation('already_voided');
    final batch = db.batch();
    batch.update(_c('expenses').doc(expense.id), {
      'voided': true,
      'voidedBy': actor.uid,
      'voidedAt': FieldValue.serverTimestamp(),
    });
    _roll(batch, expense.dayKey, _expenseDeltas(expense.amountPaise, expense.method, -1));
    _commit('voidExpense', batch);
  }

  Map<String, int> _expenseDeltas(int amount, PaymentMethod method, int sign) => {
        'expensePaise': sign * amount,
        method == PaymentMethod.cash ? 'expenseCashPaise' : 'expenseUpiPaise': sign * amount,
      };

  // ------------------------------------------------------------ suppliers

  String saveSupplier({
    String? id,
    required String name,
    String phone = '',
    String address = '',
    String gstin = '',
  }) {
    _requireManager();
    if (name.trim().isEmpty) throw const InvalidOperation('name_required');
    final ref = id == null ? _c('suppliers').doc() : _c('suppliers').doc(id);
    final batch = db.batch();
    batch.set(
      ref,
      {
        'name': name.trim(),
        'phone': phone.trim(),
        'address': address.trim(),
        'gstin': gstin.trim(),
        if (id == null) ...{'balancePaise': 0, 'archived': false},
        ..._stamp(),
      },
      SetOptions(merge: true),
    );
    _commit('saveSupplier', batch);
    return ref.id;
  }

  void archiveSupplier(String id) {
    _requireManager();
    final batch = db.batch()
      ..set(_c('suppliers').doc(id), {'archived': true, ..._stamp()}, SetOptions(merge: true));
    _commit('archiveSupplier', batch);
  }

  /// Goods received. [lines] add to stock and update cost prices; [paidPaise]
  /// is what was handed over now, and the rest goes on the supplier's account.
  void recordSupplierPurchase({
    required String supplierId,
    required int amountPaise,
    int paidPaise = 0,
    PaymentMethod method = PaymentMethod.cash,
    List<StockInLine> lines = const [],
    String note = '',
  }) {
    _requireManager();
    if (amountPaise <= 0) throw const InvalidOperation('amount_required');
    if (paidPaise < 0 || paidPaise > amountPaise) throw const InvalidOperation('invalid_paid');
    if (paidPaise > 0 && method == PaymentMethod.credit) {
      throw const InvalidOperation('invalid_method');
    }
    if (lines.length > maxCartLines) throw const InvalidOperation('too_many_lines');
    final now = _clock();
    final batch = db.batch();
    batch.set(_c('supplierTxns').doc(), {
      'supplierId': supplierId,
      'kind': SupplierTxnKind.purchase.name,
      'amountPaise': amountPaise,
      'method': null,
      'note': note.trim(),
      'at': Timestamp.fromDate(now),
      'byUid': actor.uid,
      'byName': actor.name,
    });
    for (final line in lines) {
      _moveStock(batch, line.product.id, line.qtyMilli, StockReason.purchase, note: note);
      batch.update(_c('products').doc(line.product.id), {'costPaise': line.costPaise});
    }
    if (paidPaise > 0) _addSupplierPayment(batch, supplierId, paidPaise, method, note, now);
    batch.set(
      _c('suppliers').doc(supplierId),
      {'balancePaise': FieldValue.increment(amountPaise - paidPaise), ..._stamp()},
      SetOptions(merge: true),
    );
    _roll(batch, dayKey(now), {
      'purchasePaise': amountPaise,
      if (paidPaise > 0)
        method == PaymentMethod.cash ? 'supplierCashPaise' : 'supplierUpiPaise': paidPaise,
    });
    _commit('recordSupplierPurchase', batch);
  }

  void recordSupplierPayment({
    required String supplierId,
    required int amountPaise,
    required PaymentMethod method,
    String note = '',
  }) {
    _requireManager();
    if (amountPaise <= 0) throw const InvalidOperation('amount_required');
    if (method == PaymentMethod.credit) throw const InvalidOperation('invalid_method');
    final now = _clock();
    final batch = db.batch();
    _addSupplierPayment(batch, supplierId, amountPaise, method, note, now);
    batch.set(
      _c('suppliers').doc(supplierId),
      {'balancePaise': FieldValue.increment(-amountPaise), ..._stamp()},
      SetOptions(merge: true),
    );
    _roll(batch, dayKey(now), {
      method == PaymentMethod.cash ? 'supplierCashPaise' : 'supplierUpiPaise': amountPaise,
    });
    _commit('recordSupplierPayment', batch);
  }

  // -------------------------------------------------------------- helpers

  void _addSupplierPayment(
      WriteBatch batch, String supplierId, int amount, PaymentMethod method, String note, DateTime at) {
    batch.set(_c('supplierTxns').doc(), {
      'supplierId': supplierId,
      'kind': SupplierTxnKind.payment.name,
      'amountPaise': amount,
      'method': method.name,
      'note': note.trim(),
      'at': Timestamp.fromDate(at),
      'byUid': actor.uid,
      'byName': actor.name,
    });
  }

  String _addKhata(
    WriteBatch batch, {
    String? id,
    required String customerId,
    required KhataKind kind,
    required int signedPaise,
    PaymentMethod? method,
    String? billId,
    String note = '',
    String? reversesId,
    Map<String, dynamic> customerExtra = const {},
  }) {
    final now = _clock();
    final ref = id == null ? _c('khata').doc() : _c('khata').doc(id);
    batch.set(ref, {
      'customerId': customerId,
      'kind': kind.name,
      'amountPaise': signedPaise,
      'method': method?.name,
      'billId': billId,
      'note': note.trim(),
      'reversesId': reversesId,
      'at': Timestamp.fromDate(now),
      'byUid': actor.uid,
      'byName': actor.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      _c('customers').doc(customerId),
      {
        'balancePaise': FieldValue.increment(signedPaise),
        'lastTxnAt': Timestamp.fromDate(now),
        ...customerExtra,
        ..._stamp(),
      },
      SetOptions(merge: true),
    );
    return ref.id;
  }

  void _moveStock(
    WriteBatch batch,
    String productId,
    int deltaMilli,
    StockReason reason, {
    String? refId,
    String note = '',
  }) {
    batch.set(
      _c('products').doc(productId),
      {'stockMilli': FieldValue.increment(deltaMilli), ..._stamp()},
      SetOptions(merge: true),
    );
    batch.set(_c('stockMoves').doc(), {
      'productId': productId,
      'deltaMilli': deltaMilli,
      'reason': reason.name,
      'refId': refId,
      'note': note.trim(),
      'at': Timestamp.fromDate(_clock()),
      'byUid': actor.uid,
      'byName': actor.name,
    });
  }

  void _roll(
    WriteBatch batch,
    String key,
    Map<String, int> deltas, {
    Map<String, Map<String, int>> items = const {},
  }) {
    batch.set(
      _c('days').doc(key),
      {
        'dayKey': key,
        for (final e in deltas.entries) e.key: FieldValue.increment(e.value),
        if (items.isNotEmpty)
          'items': {
            for (final item in items.entries)
              item.key: {
                for (final f in item.value.entries) f.key: FieldValue.increment(f.value),
              },
          },
      },
      SetOptions(merge: true),
    );
  }

  Map<String, dynamic> _stamp() => {'updatedAt': FieldValue.serverTimestamp()};

  void _requireManager() {
    if (!actor.role.canManage) throw const InvalidOperation('manager_only');
  }

  void _commit(String label, WriteBatch batch) {
    final monitor = sync;
    if (monitor != null) {
      monitor.track(label, batch.commit);
    } else {
      batch.commit();
    }
  }
}
