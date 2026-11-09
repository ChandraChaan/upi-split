import 'models.dart';
import 'money.dart';

/// Firestore batches hold 500 writes; each stocked line costs two.
const int maxCartLines = 200;

class CartLine {
  CartLine({
    required this.name,
    required this.unit,
    required this.qtyMilli,
    required this.pricePaise,
    this.costPaise = 0,
    this.nameTe = '',
    this.productId,
  });

  factory CartLine.fromProduct(Product p, int qtyMilli) => CartLine(
        productId: p.id,
        name: p.name,
        nameTe: p.nameTe,
        unit: p.unit,
        qtyMilli: qtyMilli,
        pricePaise: p.pricePaise,
        costPaise: p.costPaise,
      );

  final String? productId;
  final String name;
  final String nameTe;
  final Unit unit;
  int qtyMilli;
  int pricePaise;
  final int costPaise;

  int get totalPaise => lineValue(pricePaise, qtyMilli);

  BillItem toBillItem() => BillItem(
        productId: productId,
        name: name,
        nameTe: nameTe,
        unit: unit,
        qtyMilli: qtyMilli,
        pricePaise: pricePaise,
        costPaise: costPaise,
        totalPaise: totalPaise,
      );
}

class PaymentSplit {
  const PaymentSplit({this.cashPaise = 0, this.upiPaise = 0, this.creditPaise = 0});
  final int cashPaise;
  final int upiPaise;
  final int creditPaise;
  int get totalPaise => cashPaise + upiPaise + creditPaise;
}

enum CartError {
  empty,
  tooManyLines,
  invalidQuantity,
  discountTooLarge,
  paymentMismatch,
  negativePayment,
  creditNeedsCustomer,
}

class Cart {
  final List<CartLine> lines = [];
  int discountPaise = 0;

  /// Adds to an existing line of the same product, or appends a new one.
  void addProduct(Product product, int qtyMilli) {
    for (final line in lines) {
      if (line.productId == product.id) {
        line.qtyMilli += qtyMilli;
        return;
      }
    }
    lines.add(CartLine.fromProduct(product, qtyMilli));
  }

  void addCustom(String name, int pricePaise, {int qtyMilli = 1000}) {
    lines.add(CartLine(
      name: name,
      unit: Unit.piece,
      qtyMilli: qtyMilli,
      pricePaise: pricePaise,
    ));
  }

  void clear() {
    lines.clear();
    discountPaise = 0;
  }

  bool get isEmpty => lines.isEmpty;
  int get subtotalPaise => lines.fold(0, (sum, l) => sum + l.totalPaise);
  int get totalPaise => subtotalPaise - discountPaise;

  /// Returns the first problem that would make this bill invalid.
  CartError? validate(PaymentSplit payment, {Customer? customer}) {
    if (lines.isEmpty) return CartError.empty;
    if (lines.length > maxCartLines) return CartError.tooManyLines;
    if (lines.any((l) => l.qtyMilli <= 0 || l.pricePaise < 0)) {
      return CartError.invalidQuantity;
    }
    if (discountPaise < 0 || discountPaise > subtotalPaise) {
      return CartError.discountTooLarge;
    }
    if (payment.cashPaise < 0 || payment.upiPaise < 0 || payment.creditPaise < 0) {
      return CartError.negativePayment;
    }
    if (payment.totalPaise != totalPaise) return CartError.paymentMismatch;
    if (payment.creditPaise > 0 && customer == null) {
      return CartError.creditNeedsCustomer;
    }
    return null;
  }

  /// True when this sale would take [customer] past their credit limit.
  /// A warning for the cashier rather than a hard stop.
  bool exceedsCreditLimit(PaymentSplit payment, Customer customer) =>
      customer.creditLimitPaise > 0 &&
      customer.balancePaise + payment.creditPaise > customer.creditLimitPaise;
}
