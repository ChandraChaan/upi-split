import 'cart.dart';
import 'models.dart';

/// One amount on the sell keypad's tape: a price, optionally times a count,
/// as in "5 × ₹2" for five toffees.
class TapeEntry {
  const TapeEntry(this.pricePaise, [this.count = 1]);
  final int pricePaise;
  final int count;
  int get totalPaise => pricePaise * count;
}

/// The sell keypad. Amounts are whole rupees, because loose counter sales
/// are; a typed amount can be multiplied by a count with ×.
class CounterTape {
  static const _maxPriceDigits = 6;
  static const _maxCountDigits = 3;
  static const times = '×';

  /// Lines a single sale may hold, well inside a bill's limit.
  static const maxEntries = 100;

  final List<TapeEntry> entries = [];
  String _typed = '';

  /// What is being typed, for example "10" or "2×5".
  String get typed => _typed;

  /// The typed amount, or null while nothing usable is typed.
  TapeEntry? get pending => parseEntry(_typed);

  int get totalPaise =>
      entries.fold(0, (sum, e) => sum + e.totalPaise) + (pending?.totalPaise ?? 0);

  bool get isEmpty => totalPaise == 0;
  bool get isFull => entries.length >= maxEntries;

  void digit(String d) {
    assert(d == '0' || d == '00' || int.tryParse(d) != null);
    final parts = _typed.split(times);
    final limit = parts.length == 1 ? _maxPriceDigits : _maxCountDigits;
    // No leading zeros, so a 0 typed first does nothing.
    final next = (parts.last + d).replaceFirst(RegExp('^0+'), '');
    if (next.isEmpty || next.length > limit) return;
    parts[parts.length - 1] = next;
    _typed = parts.join(times);
  }

  /// Starts the count after a typed price. Ignored without a price, or twice.
  void multiply() {
    if (_typed.isEmpty || _typed.contains(times)) return;
    _typed = '$_typed$times';
  }

  void backspace() {
    if (_typed.isEmpty) return;
    _typed = _typed.substring(0, _typed.length - 1);
  }

  /// Clears what is being typed, or the whole sale if nothing is.
  void clear() {
    if (_typed.isNotEmpty) {
      _typed = '';
    } else {
      entries.clear();
    }
  }

  /// Moves the typed amount onto the tape. False when nothing usable is typed.
  bool commit() {
    final entry = pending;
    if (entry == null || isFull) return false;
    entries.add(entry);
    _typed = '';
    return true;
  }

  /// A one-tap amount such as ₹2. Whatever was typed is added first.
  void add(int rupees) {
    commit();
    if (isFull) return;
    entries.add(TapeEntry(rupees * 100));
  }

  void removeAt(int index) => entries.removeAt(index);

  /// Everything on the tape, including what is typed, and empties it.
  List<TapeEntry> takeAll() {
    commit();
    final all = List<TapeEntry>.of(entries);
    entries.clear();
    _typed = '';
    return all;
  }

  static TapeEntry? parseEntry(String text) {
    if (text.isEmpty) return null;
    final parts = text.split(times);
    final price = int.tryParse(parts.first);
    if (price == null || price <= 0) return null;
    // "10×" with no count yet counts as one.
    final count = parts.length > 1 && parts[1].isNotEmpty ? int.tryParse(parts[1]) : 1;
    if (count == null || count <= 0) return null;
    return TapeEntry(price * 100, count);
  }
}

/// How a counter sale settles when the customer pays only part of it now,
/// or pays more to clear earlier dues.
class CounterPayment {
  const CounterPayment._(this.split, this.towardsDuesPaise);

  /// [paidPaise] is what the customer handed over now, in [method].
  factory CounterPayment.settle({
    required int totalPaise,
    required int paidPaise,
    PaymentMethod method = PaymentMethod.cash,
  }) {
    assert(method != PaymentMethod.credit);
    final paid = paidPaise < 0 ? 0 : paidPaise;
    final forSale = paid < totalPaise ? paid : totalPaise;
    return CounterPayment._(
      PaymentSplit(
        cashPaise: method == PaymentMethod.cash ? forSale : 0,
        upiPaise: method == PaymentMethod.upi ? forSale : 0,
        creditPaise: totalPaise - forSale,
      ),
      paid - forSale,
    );
  }

  /// What goes on the bill; its credit part is added to the khata.
  final PaymentSplit split;

  /// Paid beyond this sale; it comes off the customer's earlier dues.
  final int towardsDuesPaise;
}

/// A saved counter sale, kept so it can be undone in one step.
class CounterSale {
  const CounterSale({
    required this.bill,
    this.paymentId,
    this.paymentPaise = 0,
    this.paymentMethod,
  });
  final Bill bill;

  /// The khata payment for anything paid towards earlier dues.
  final String? paymentId;
  final int paymentPaise;
  final PaymentMethod? paymentMethod;
}
