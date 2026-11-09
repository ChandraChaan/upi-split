import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;

DateTime _date(Object? value) =>
    value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
DateTime? _dateOrNull(Object? value) => value is Timestamp ? value.toDate() : null;
int _int(Object? value) => value is num ? value.toInt() : 0;
String _str(Object? value) => value is String ? value : '';
T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

enum MemberRole {
  owner,
  manager,
  cashier;

  bool get canManage => this != MemberRole.cashier;
  bool get isOwner => this == MemberRole.owner;
}

enum PaymentMethod { cash, upi, credit }

enum Unit { piece, kg, litre, packet }

enum KhataKind { purchase, payment, adjustment }

enum SupplierTxnKind { purchase, payment }

enum StockReason { sale, purchase, adjustment, voidSale }

class Actor {
  const Actor({required this.uid, required this.name, required this.role});
  final String uid;
  final String name;
  final MemberRole role;
}

class Business {
  const Business({required this.id, required this.name, required this.ownerUid});
  factory Business.fromMap(String id, Json m) =>
      Business(id: id, name: _str(m['name']), ownerUid: _str(m['ownerUid']));
  final String id;
  final String name;
  final String ownerUid;
}

class Member {
  const Member({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.storeIds,
    required this.active,
  });
  factory Member.fromMap(String uid, Json m) => Member(
        uid: uid,
        name: _str(m['name']),
        email: _str(m['email']),
        role: _enum(MemberRole.values, m['role'], MemberRole.cashier),
        storeIds: List<String>.from(m['storeIds'] as List? ?? const []),
        active: m['active'] == true,
      );
  final String uid;
  final String name;
  final String email;
  final MemberRole role;
  final List<String> storeIds;
  final bool active;

  bool canAccess(String storeId) => role.isOwner || storeIds.contains(storeId);
}

class Store {
  const Store({
    required this.id,
    required this.name,
    this.address = '',
    this.phone = '',
    this.gstin = '',
    this.upiId = '',
    this.receiptFooter = '',
  });
  factory Store.fromMap(String id, Json m) => Store(
        id: id,
        name: _str(m['name']),
        address: _str(m['address']),
        phone: _str(m['phone']),
        gstin: _str(m['gstin']),
        upiId: _str(m['upiId']),
        receiptFooter: _str(m['receiptFooter']),
      );
  final String id;
  final String name;
  final String address;
  final String phone;
  final String gstin;
  final String upiId;
  final String receiptFooter;

  Json toMap() => {
        'name': name,
        'address': address,
        'phone': phone,
        'gstin': gstin,
        'upiId': upiId,
        'receiptFooter': receiptFooter,
      };
}

class Invite {
  const Invite({
    required this.code,
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.storeIds,
    required this.expiresAt,
    this.usedBy,
  });
  factory Invite.fromMap(String code, Json m) => Invite(
        code: code,
        businessId: _str(m['businessId']),
        businessName: _str(m['businessName']),
        role: _enum(MemberRole.values, m['role'], MemberRole.cashier),
        storeIds: List<String>.from(m['storeIds'] as List? ?? const []),
        expiresAt: _date(m['expiresAt']),
        usedBy: m['usedBy'] as String?,
      );
  final String code;
  final String businessId;
  final String businessName;
  final MemberRole role;
  final List<String> storeIds;
  final DateTime expiresAt;
  final String? usedBy;
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.creditLimitPaise = 0,
    this.balancePaise = 0,
    this.dueDate,
    this.lastTxnAt,
    this.lastReminderAt,
    this.archived = false,
  });
  factory Customer.fromMap(String id, Json m) => Customer(
        id: id,
        name: _str(m['name']),
        phone: _str(m['phone']),
        address: _str(m['address']),
        creditLimitPaise: _int(m['creditLimitPaise']),
        balancePaise: _int(m['balancePaise']),
        dueDate: _dateOrNull(m['dueDate']),
        lastTxnAt: _dateOrNull(m['lastTxnAt']),
        lastReminderAt: _dateOrNull(m['lastReminderAt']),
        archived: m['archived'] == true,
      );
  final String id;
  final String name;
  final String phone;
  final String address;

  /// 0 means no limit is enforced.
  final int creditLimitPaise;

  /// Positive: the customer owes the shop. Negative: advance held.
  final int balancePaise;
  final DateTime? dueDate;
  final DateTime? lastTxnAt;
  final DateTime? lastReminderAt;
  final bool archived;

  bool get hasDues => balancePaise > 0;
  bool isOverdue(DateTime now) =>
      hasDues && dueDate != null && dueDate!.isBefore(now);
}

class KhataEntry {
  const KhataEntry({
    required this.id,
    required this.customerId,
    required this.kind,
    required this.amountPaise,
    required this.at,
    required this.byUid,
    required this.byName,
    this.method,
    this.billId,
    this.note = '',
    this.reversesId,
  });
  factory KhataEntry.fromMap(String id, Json m) => KhataEntry(
        id: id,
        customerId: _str(m['customerId']),
        kind: _enum(KhataKind.values, m['kind'], KhataKind.adjustment),
        amountPaise: _int(m['amountPaise']),
        at: _date(m['at']),
        byUid: _str(m['byUid']),
        byName: _str(m['byName']),
        method: m['method'] == null
            ? null
            : _enum(PaymentMethod.values, m['method'], PaymentMethod.cash),
        billId: m['billId'] as String?,
        note: _str(m['note']),
        reversesId: m['reversesId'] as String?,
      );
  final String id;
  final String customerId;
  final KhataKind kind;

  /// Signed effect on the customer's balance: positive adds to dues.
  final int amountPaise;
  final DateTime at;
  final String byUid;
  final String byName;
  final PaymentMethod? method;
  final String? billId;
  final String note;
  final String? reversesId;
}

class Product {
  const Product({
    required this.id,
    required this.name,
    this.nameTe = '',
    this.barcode = '',
    this.category = '',
    this.unit = Unit.piece,
    this.pricePaise = 0,
    this.costPaise = 0,
    this.stockMilli = 0,
    this.lowStockMilli = 0,
    this.active = true,
  });
  factory Product.fromMap(String id, Json m) => Product(
        id: id,
        name: _str(m['name']),
        nameTe: _str(m['nameTe']),
        barcode: _str(m['barcode']),
        category: _str(m['category']),
        unit: _enum(Unit.values, m['unit'], Unit.piece),
        pricePaise: _int(m['pricePaise']),
        costPaise: _int(m['costPaise']),
        stockMilli: _int(m['stockMilli']),
        lowStockMilli: _int(m['lowStockMilli']),
        active: m['active'] != false,
      );
  final String id;
  final String name;
  final String nameTe;
  final String barcode;
  final String category;
  final Unit unit;

  /// Selling price and purchase cost, per whole unit.
  final int pricePaise;
  final int costPaise;
  final int stockMilli;
  final int lowStockMilli;
  final bool active;

  bool get isLowStock => lowStockMilli > 0 && stockMilli <= lowStockMilli;
  String displayName(String language) =>
      language == 'te' && nameTe.isNotEmpty ? nameTe : name;

  Json toMap() => {
        'name': name,
        'nameTe': nameTe,
        'barcode': barcode,
        'category': category,
        'unit': unit.name,
        'pricePaise': pricePaise,
        'costPaise': costPaise,
        'lowStockMilli': lowStockMilli,
        'active': active,
      };
}

class BillItem {
  const BillItem({
    required this.name,
    required this.unit,
    required this.qtyMilli,
    required this.pricePaise,
    required this.costPaise,
    required this.totalPaise,
    this.nameTe = '',
    this.productId,
  });
  factory BillItem.fromMap(Json m) => BillItem(
        productId: m['productId'] as String?,
        name: _str(m['name']),
        nameTe: _str(m['nameTe']),
        unit: _enum(Unit.values, m['unit'], Unit.piece),
        qtyMilli: _int(m['qtyMilli']),
        pricePaise: _int(m['pricePaise']),
        costPaise: _int(m['costPaise']),
        totalPaise: _int(m['totalPaise']),
      );

  /// Null for a free-form line that is not in the catalogue.
  final String? productId;
  final String name;
  final String nameTe;
  final Unit unit;
  final int qtyMilli;
  final int pricePaise;
  final int costPaise;
  final int totalPaise;

  int get cogsPaise => productId == null ? 0 : _cogs;
  int get _cogs {
    final raw = costPaise * qtyMilli;
    return (raw + 500) ~/ 1000;
  }

  String displayName(String language) =>
      language == 'te' && nameTe.isNotEmpty ? nameTe : name;

  Json toMap() => {
        'productId': productId,
        'name': name,
        'nameTe': nameTe,
        'unit': unit.name,
        'qtyMilli': qtyMilli,
        'pricePaise': pricePaise,
        'costPaise': costPaise,
        'totalPaise': totalPaise,
      };
}

class Bill {
  const Bill({
    required this.id,
    required this.number,
    required this.items,
    required this.subtotalPaise,
    required this.discountPaise,
    required this.totalPaise,
    required this.cashPaise,
    required this.upiPaise,
    required this.creditPaise,
    required this.at,
    required this.dayKey,
    required this.byUid,
    required this.byName,
    this.customerId,
    this.customerName = '',
    this.customerPhone = '',
    this.voided = false,
    this.voidReason = '',
  });
  factory Bill.fromMap(String id, Json m) => Bill(
        id: id,
        number: _str(m['number']),
        items: (m['items'] as List? ?? const [])
            .map((e) => BillItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        subtotalPaise: _int(m['subtotalPaise']),
        discountPaise: _int(m['discountPaise']),
        totalPaise: _int(m['totalPaise']),
        cashPaise: _int(m['cashPaise']),
        upiPaise: _int(m['upiPaise']),
        creditPaise: _int(m['creditPaise']),
        at: _date(m['at']),
        dayKey: _str(m['dayKey']),
        byUid: _str(m['byUid']),
        byName: _str(m['byName']),
        customerId: m['customerId'] as String?,
        customerName: _str(m['customerName']),
        customerPhone: _str(m['customerPhone']),
        voided: m['voided'] == true,
        voidReason: _str(m['voidReason']),
      );
  final String id;
  final String number;
  final List<BillItem> items;
  final int subtotalPaise;
  final int discountPaise;
  final int totalPaise;
  final int cashPaise;
  final int upiPaise;
  final int creditPaise;
  final DateTime at;
  final String dayKey;
  final String byUid;
  final String byName;
  final String? customerId;
  final String customerName;
  final String customerPhone;
  final bool voided;
  final String voidReason;

  int get cogsPaise => items.fold(0, (total, i) => total + i.cogsPaise);
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amountPaise,
    required this.method,
    required this.at,
    required this.dayKey,
    required this.byUid,
    required this.byName,
    this.note = '',
    this.voided = false,
  });
  factory Expense.fromMap(String id, Json m) => Expense(
        id: id,
        category: _str(m['category']),
        amountPaise: _int(m['amountPaise']),
        method: _enum(PaymentMethod.values, m['method'], PaymentMethod.cash),
        at: _date(m['at']),
        dayKey: _str(m['dayKey']),
        byUid: _str(m['byUid']),
        byName: _str(m['byName']),
        note: _str(m['note']),
        voided: m['voided'] == true,
      );
  final String id;
  final String category;
  final int amountPaise;
  final PaymentMethod method;
  final DateTime at;
  final String dayKey;
  final String byUid;
  final String byName;
  final String note;
  final bool voided;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.phone = '',
    this.address = '',
    this.gstin = '',
    this.balancePaise = 0,
    this.archived = false,
  });
  factory Supplier.fromMap(String id, Json m) => Supplier(
        id: id,
        name: _str(m['name']),
        phone: _str(m['phone']),
        address: _str(m['address']),
        gstin: _str(m['gstin']),
        balancePaise: _int(m['balancePaise']),
        archived: m['archived'] == true,
      );
  final String id;
  final String name;
  final String phone;
  final String address;
  final String gstin;

  /// Positive: the shop owes this supplier.
  final int balancePaise;
  final bool archived;
}

class SupplierTxn {
  const SupplierTxn({
    required this.id,
    required this.supplierId,
    required this.kind,
    required this.amountPaise,
    required this.at,
    required this.byName,
    this.method,
    this.note = '',
  });
  factory SupplierTxn.fromMap(String id, Json m) => SupplierTxn(
        id: id,
        supplierId: _str(m['supplierId']),
        kind: _enum(SupplierTxnKind.values, m['kind'], SupplierTxnKind.purchase),
        amountPaise: _int(m['amountPaise']),
        at: _date(m['at']),
        byName: _str(m['byName']),
        method: m['method'] == null
            ? null
            : _enum(PaymentMethod.values, m['method'], PaymentMethod.cash),
        note: _str(m['note']),
      );
  final String id;
  final String supplierId;
  final SupplierTxnKind kind;

  /// Always positive; [kind] says which way it moves the balance.
  final int amountPaise;
  final DateTime at;
  final String byName;
  final PaymentMethod? method;
  final String note;
}

class StockMove {
  const StockMove({
    required this.id,
    required this.productId,
    required this.deltaMilli,
    required this.reason,
    required this.at,
    required this.byName,
    this.note = '',
  });
  factory StockMove.fromMap(String id, Json m) => StockMove(
        id: id,
        productId: _str(m['productId']),
        deltaMilli: _int(m['deltaMilli']),
        reason: _enum(StockReason.values, m['reason'], StockReason.adjustment),
        at: _date(m['at']),
        byName: _str(m['byName']),
        note: _str(m['note']),
      );
  final String id;
  final String productId;
  final int deltaMilli;
  final StockReason reason;
  final DateTime at;
  final String byName;
  final String note;
}

/// Per-product line of a daily rollup.
class DayItem {
  const DayItem({required this.qtyMilli, required this.revenuePaise, required this.cogsPaise});
  final int qtyMilli;
  final int revenuePaise;
  final int cogsPaise;
}

/// One store's counters for one calendar day, kept with atomic increments so
/// that offline devices merge correctly when they reconnect.
class DayRollup {
  const DayRollup({
    required this.dayKey,
    this.salesPaise = 0,
    this.discountPaise = 0,
    this.billCount = 0,
    this.cogsPaise = 0,
    this.cashSalesPaise = 0,
    this.upiSalesPaise = 0,
    this.creditSalesPaise = 0,
    this.collectionCashPaise = 0,
    this.collectionUpiPaise = 0,
    this.expensePaise = 0,
    this.expenseCashPaise = 0,
    this.expenseUpiPaise = 0,
    this.purchasePaise = 0,
    this.supplierCashPaise = 0,
    this.supplierUpiPaise = 0,
    this.items = const {},
  });
  factory DayRollup.fromMap(String id, Json m) => DayRollup(
        dayKey: id,
        salesPaise: _int(m['salesPaise']),
        discountPaise: _int(m['discountPaise']),
        billCount: _int(m['billCount']),
        cogsPaise: _int(m['cogsPaise']),
        cashSalesPaise: _int(m['cashSalesPaise']),
        upiSalesPaise: _int(m['upiSalesPaise']),
        creditSalesPaise: _int(m['creditSalesPaise']),
        collectionCashPaise: _int(m['collectionCashPaise']),
        collectionUpiPaise: _int(m['collectionUpiPaise']),
        expensePaise: _int(m['expensePaise']),
        expenseCashPaise: _int(m['expenseCashPaise']),
        expenseUpiPaise: _int(m['expenseUpiPaise']),
        purchasePaise: _int(m['purchasePaise']),
        supplierCashPaise: _int(m['supplierCashPaise']),
        supplierUpiPaise: _int(m['supplierUpiPaise']),
        items: (m['items'] as Map? ?? const {}).map((k, v) {
          final item = Map<String, dynamic>.from(v as Map);
          return MapEntry(
            k as String,
            DayItem(
              qtyMilli: _int(item['q']),
              revenuePaise: _int(item['r']),
              cogsPaise: _int(item['c']),
            ),
          );
        }),
      );
  final String dayKey;
  final int salesPaise;
  final int discountPaise;
  final int billCount;
  final int cogsPaise;
  final int cashSalesPaise;
  final int upiSalesPaise;
  final int creditSalesPaise;
  final int collectionCashPaise;
  final int collectionUpiPaise;
  final int expensePaise;
  final int expenseCashPaise;
  final int expenseUpiPaise;
  final int purchasePaise;
  final int supplierCashPaise;
  final int supplierUpiPaise;
  final Map<String, DayItem> items;

  int get grossProfitPaise => salesPaise - cogsPaise;
  int get netProfitPaise => grossProfitPaise - expensePaise;

  /// Money that should have moved through the cash drawer today.
  int get netCashPaise =>
      cashSalesPaise + collectionCashPaise - expenseCashPaise - supplierCashPaise;
  int get netUpiPaise =>
      upiSalesPaise + collectionUpiPaise - expenseUpiPaise - supplierUpiPaise;
}
