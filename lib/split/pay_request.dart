import 'package:upi_kit/upi_kit.dart';

/// Where the app is published. Share links point here so friends can open
/// them in any browser, including WhatsApp's.
const defaultSiteUrl = 'https://chandrachaan.github.io/upi-split/';

/// One friend's share of a bill, as sent to them.
///
/// It travels in the link's `#fragment`, which browsers never send to a
/// server, so the amount and UPI ID stay between you and your friend.
class PayRequest {
  const PayRequest({
    required this.payeeVpa,
    required this.payeeName,
    required this.amountPaise,
    this.note = '',
    this.friendName = '',
  });

  final String payeeVpa;
  final String payeeName;
  final int amountPaise;
  final String note;

  /// Who the request is for, so the page can greet them.
  final String friendName;

  UpiAmount get amount => UpiAmount.paise(amountPaise);

  /// The UPI payment link this request stands for.
  UpiPaymentLink get upiLink => UpiPaymentLink(
    payeeVpa: payeeVpa,
    payeeName: payeeName,
    amount: amount,
    note: note.isEmpty ? null : _truncate(note, 50),
  );

  /// A link to the pay page, safe to send in any chat app.
  ///
  /// WhatsApp and SMS apps don't make `upi://` links tappable, so friends get
  /// an ordinary web link; the page opens their UPI app.
  String shareUrl([String siteUrl = defaultSiteUrl]) {
    final query = Uri(
      queryParameters: {
        'pa': payeeVpa,
        'pn': payeeName,
        'am': amount.format(),
        if (note.isNotEmpty) 'tn': note,
        if (friendName.isNotEmpty) 'to': friendName,
      },
    ).query;
    return '$siteUrl#/pay?$query';
  }

  /// Reads a request from a page's URL fragment, such as
  /// `/pay?pa=…&pn=…&am=…`. Returns null if it isn't a valid request.
  static PayRequest? fromFragment(String fragment) {
    final f = fragment.startsWith('#') ? fragment.substring(1) : fragment;
    if (!f.startsWith('/pay?')) return null;
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(f.substring('/pay?'.length));
    } on FormatException {
      return null;
    }
    final vpa = params['pa'];
    final amount = UpiAmount.tryParse(params['am'] ?? '');
    if (vpa == null || !Vpa.isValid(vpa) || amount == null || amount.isZero) {
      return null;
    }
    return PayRequest(
      payeeVpa: vpa.trim(),
      payeeName: params['pn'] ?? '',
      amountPaise: amount.paise,
      note: params['tn'] ?? '',
      friendName: params['to'] ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PayRequest &&
      other.payeeVpa == payeeVpa &&
      other.payeeName == payeeName &&
      other.amountPaise == amountPaise &&
      other.note == note &&
      other.friendName == friendName;

  @override
  int get hashCode =>
      Object.hash(payeeVpa, payeeName, amountPaise, note, friendName);
}

/// Indian rupee formatting with lakh grouping: ₹1,23,456.50.
String formatRupees(int paise) {
  final rupees = (paise ~/ 100).toString();
  final fraction = (paise % 100).toString().padLeft(2, '0');
  String grouped;
  if (rupees.length <= 3) {
    grouped = rupees;
  } else {
    final last3 = rupees.substring(rupees.length - 3);
    var rest = rupees.substring(0, rupees.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return fraction == '00' ? '₹$grouped' : '₹$grouped.$fraction';
}

/// The message to send one friend, for WhatsApp or any chat app.
String messageFor(PayRequest request, {String siteUrl = defaultSiteUrl}) {
  final greeting = request.friendName.isEmpty
      ? 'Hi'
      : 'Hi ${request.friendName}';
  final what = request.note.isEmpty ? '' : ' for ${request.note}';
  return '$greeting, your share$what is ${formatRupees(request.amountPaise)}. '
      'Pay ${request.payeeName.isEmpty ? request.payeeVpa : request.payeeName} '
      'with any UPI app here: ${request.shareUrl(siteUrl)}';
}

String _truncate(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);
