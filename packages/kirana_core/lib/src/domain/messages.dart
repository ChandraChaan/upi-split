import 'package:intl/intl.dart';

import 'models.dart';
import 'money.dart';

/// Keeps the last ten digits and prefixes India's country code.
/// Returns null when the number is not a usable 10-digit mobile.
String? normalizeIndianPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10) return null;
  final last10 = digits.substring(digits.length - 10);
  if (!RegExp(r'^[6-9]').hasMatch(last10)) return null;
  return '91$last10';
}

/// Opens WhatsApp with the message filled in; the user presses send.
Uri? whatsappUri(String phone, String message) {
  final normalized = normalizeIndianPhone(phone);
  if (normalized == null) return null;
  return Uri.parse(
      'https://wa.me/$normalized?text=${Uri.encodeComponent(message)}');
}

/// Opens the SMS app with the message filled in; the user presses send.
Uri? smsUri(String phone, String message) {
  final normalized = normalizeIndianPhone(phone);
  if (normalized == null) return null;
  return Uri.parse('sms:+$normalized?body=${Uri.encodeComponent(message)}');
}

String reminderMessage({
  required String language,
  required String shopName,
  required Customer customer,
  String upiId = '',
}) {
  final amount = formatRupees(customer.balancePaise);
  final due = customer.dueDate == null
      ? ''
      : DateFormat('dd/MM/yyyy').format(customer.dueDate!);
  if (language == 'te') {
    final dueLine = due.isEmpty ? '' : ' చెల్లించాల్సిన తేదీ: $due.';
    final upiLine = upiId.isEmpty ? '' : '\nUPI: $upiId';
    return 'నమస్కారం ${customer.name} గారు, $shopName లో మీ బాకీ $amount ఉంది.'
        '$dueLine దయచేసి చెల్లించండి. ధన్యవాదాలు.$upiLine';
  }
  final dueLine = due.isEmpty ? '' : ' Due date: $due.';
  final upiLine = upiId.isEmpty ? '' : '\nUPI: $upiId';
  return 'Hello ${customer.name}, your outstanding balance at $shopName is '
      '$amount.$dueLine Please pay at your convenience. Thank you.$upiLine';
}

/// Plain-text receipt for SMS and WhatsApp sharing.
String receiptText({
  required String language,
  required Store store,
  required Bill bill,
}) {
  final te = language == 'te';
  final when = DateFormat('dd/MM/yyyy hh:mm a').format(bill.at);
  final buffer = StringBuffer()
    ..writeln(store.name)
    ..writeln('${te ? 'బిల్లు' : 'Bill'}: ${bill.number}')
    ..writeln(when);
  if (bill.voided) buffer.writeln(te ? '*** రద్దు చేయబడింది ***' : '*** VOID ***');
  buffer.writeln('----------------');
  for (final item in bill.items) {
    buffer.writeln('${item.displayName(language)} '
        '${formatQuantity(item.qtyMilli)} x ${formatRupees(item.pricePaise)}'
        ' = ${formatRupees(item.totalPaise)}');
  }
  buffer.writeln('----------------');
  if (bill.discountPaise > 0) {
    buffer.writeln('${te ? 'తగ్గింపు' : 'Discount'}: ${formatRupees(bill.discountPaise)}');
  }
  buffer.writeln('${te ? 'మొత్తం' : 'Total'}: ${formatRupees(bill.totalPaise)}');
  if (bill.cashPaise > 0) {
    buffer.writeln('${te ? 'నగదు' : 'Cash'}: ${formatRupees(bill.cashPaise)}');
  }
  if (bill.upiPaise > 0) buffer.writeln('UPI: ${formatRupees(bill.upiPaise)}');
  if (bill.creditPaise > 0) {
    buffer.writeln('${te ? 'ఖాతాలో' : 'On credit'}: ${formatRupees(bill.creditPaise)}');
  }
  if (store.receiptFooter.isNotEmpty) buffer.writeln(store.receiptFooter);
  return buffer.toString().trimRight();
}
