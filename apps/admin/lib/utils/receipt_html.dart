import 'package:kirana_core/kirana_core.dart';

import 'dates.dart';

String escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

/// A standalone page for the browser to print. Text comes from staff input, so
/// all of it is escaped. [tr] is bound to the receipt's language.
String receiptHtml({
  required Tr tr,
  required String language,
  required Store store,
  required Bill bill,
}) {
  final e = escapeHtml;
  String row(String label, String value, {bool strong = false}) =>
      '<tr class="${strong ? 'strong' : ''}"><td>${e(label)}</td><td class="num">${e(value)}</td></tr>';
  final items = StringBuffer();
  for (final item in bill.items) {
    items.write('<tr><td>${e(item.displayName(language))}<div class="sub">'
        '${e(formatQuantity(item.qtyMilli))} x ${e(formatRupees(item.pricePaise))}</div></td>'
        '<td class="num">${e(formatRupees(item.totalPaise))}</td></tr>');
  }
  final totals = StringBuffer();
  if (bill.discountPaise > 0) {
    totals
      ..write(row(tr('subtotal'), formatRupees(bill.subtotalPaise)))
      ..write(row(tr('discount'), formatRupees(bill.discountPaise)));
  }
  totals.write(row(tr('total'), formatRupees(bill.totalPaise), strong: true));
  if (bill.cashPaise > 0) totals.write(row(tr('cash'), formatRupees(bill.cashPaise)));
  if (bill.upiPaise > 0) totals.write(row(tr('upi'), formatRupees(bill.upiPaise)));
  if (bill.creditPaise > 0) totals.write(row(tr('credit'), formatRupees(bill.creditPaise)));

  return '''<!doctype html>
<html lang="${e(language)}"><head><meta charset="utf-8"><title>${e(bill.number)}</title>
<style>
@page { margin: 8mm; }
body { font-family: "Noto Sans Telugu", "Nirmala UI", Gautami, system-ui, sans-serif; font-size: 13px; color: #000; max-width: 320px; margin: 0 auto; }
h1 { font-size: 17px; margin: 0; text-align: center; }
.center { text-align: center; }
.sub { font-size: 11px; color: #333; }
table { width: 100%; border-collapse: collapse; }
td { padding: 3px 0; vertical-align: top; }
.num { text-align: right; white-space: nowrap; padding-left: 8px; }
hr { border: 0; border-top: 1px dashed #000; margin: 8px 0; }
.strong td { font-weight: 700; font-size: 15px; }
.void { font-weight: 700; text-align: center; border: 2px solid #000; padding: 4px; margin: 8px 0; }
</style></head><body>
<h1>${e(store.name)}</h1>
${store.address.isEmpty ? '' : '<div class="center">${e(store.address)}</div>'}
${store.phone.isEmpty ? '' : '<div class="center">${e(tr('phone'))}: ${e(store.phone)}</div>'}
${store.gstin.isEmpty ? '' : '<div class="center">GSTIN: ${e(store.gstin)}</div>'}
<hr>
<div>${e(tr('bill'))}: ${e(bill.number)}</div>
<div>${e(formatDateTime(bill.at))}</div>
${bill.customerName.isEmpty ? '' : '<div>${e(tr('customer'))}: ${e(bill.customerName)}</div>'}
${bill.voided ? '<div class="void">${e(tr('voided'))}: ${e(bill.voidReason)}</div>' : ''}
<hr>
<table>$items</table>
<hr>
<table>$totals</table>
${store.receiptFooter.isEmpty ? '' : '<hr><div class="center">${e(store.receiptFooter)}</div>'}
</body></html>''';
}
