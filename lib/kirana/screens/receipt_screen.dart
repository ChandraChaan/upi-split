import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'bills_screen.dart';

Future<Uint8List> _renderPng(RenderRepaintBoundary boundary) async {
  // Long bills would otherwise exceed the GPU's texture limit.
  final ratio = math.min(3.0, 8000 / boundary.size.longestSide);
  final image = await boundary.toImage(pixelRatio: ratio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.bill, this.justSaved = false});

  /// Shown at once, even offline. Later changes (a void) arrive by stream.
  final Bill bill;
  final bool justSaved;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _receiptKey = GlobalKey();
  late final Stream<Bill?> _stream = context.session.repository.bill(
    widget.bill.id,
  );
  bool _sharing = false;

  /// Renders the receipt in Flutter so Telugu is shaped correctly in the image.
  Future<void> _shareImage(Bill bill) async {
    if (_sharing) return;
    final tr = context.trNow;
    _sharing = true;
    try {
      final boundary =
          _receiptKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final bytes = await _renderPng(boundary);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/receipt_${bill.id}.png');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
      );
    } catch (e) {
      debugPrint('Receipt image share failed: $e');
      if (mounted) showMessage(context, tr('share_failed'));
    } finally {
      _sharing = false;
    }
  }

  Future<void> _shareText(Bill bill) async {
    final tr = context.trNow;
    final session = context.session;
    final text = receiptText(
      language: session.language,
      store: session.store!,
      bill: bill,
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      debugPrint('Receipt text share failed: $e');
      if (mounted) showMessage(context, tr('share_failed'));
    }
  }

  Future<void> _sendWhatsApp(Bill bill) async {
    final tr = context.trNow;
    final session = context.session;
    final text = receiptText(
      language: session.language,
      store: session.store!,
      bill: bill,
    );
    final uri = whatsappUri(bill.customerPhone, text);
    if (uri == null) {
      showMessage(context, tr('reminder_invalid_phone'));
      return;
    }
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('WhatsApp launch failed: $e');
    }
    if (!opened && mounted) showMessage(context, tr('open_app_failed'));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final manager = context.canManage;
    return StreamBuilder<Bill?>(
      stream: _stream,
      initialData: widget.bill,
      builder: (context, snapshot) {
        final bill = snapshot.data ?? widget.bill;
        final store = context.session.store;
        return Scaffold(
          appBar: KiranaBar(
            title: tr('receipt'),
            actions: [
              if (manager && !bill.voided)
                IconButton(
                  key: const Key('receipt_void'),
                  tooltip: tr('void_bill'),
                  icon: const Icon(Icons.block),
                  onPressed: () => askVoidBill(context, bill),
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: store == null
                ? const SizedBox.shrink()
                : RepaintBoundary(
                    key: _receiptKey,
                    child: ReceiptView(
                      store: store,
                      bill: bill,
                      tr: tr,
                      language: language,
                    ),
                  ),
          ),
          bottomNavigationBar: BottomAction(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('share_image'),
                      icon: const Icon(Icons.image_outlined),
                      label: Text(tr('share_image')),
                      onPressed: () => _shareImage(bill),
                    ),
                    OutlinedButton.icon(
                      key: const Key('share_text'),
                      icon: const Icon(Icons.notes),
                      label: Text(tr('share_text')),
                      onPressed: () => _shareText(bill),
                    ),
                    if (bill.customerPhone.isNotEmpty)
                      OutlinedButton.icon(
                        key: const Key('share_whatsapp'),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(tr('whatsapp')),
                        onPressed: () => _sendWhatsApp(bill),
                      ),
                  ],
                ),
                if (widget.justSaved) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('receipt_new_bill'),
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('new_bill')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The paper-like receipt. Always black on white so the shared image reads
/// the same on any phone.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.store,
    required this.bill,
    required this.tr,
    required this.language,
  });

  final Store store;
  final Bill bill;
  final Tr tr;
  final String language;

  @override
  Widget build(BuildContext context) {
    const ink = Colors.black87;
    const body = TextStyle(color: ink, fontSize: 15, height: 1.35);
    final bold = body.copyWith(fontWeight: FontWeight.w700);
    Widget row(String label, int paise, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? bold.copyWith(fontSize: 19) : body,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatRupees(paise),
            style: strong ? bold.copyWith(fontSize: 19) : bold,
          ),
        ],
      ),
    );
    final divider = Divider(color: Colors.grey.shade400, height: 20);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            store.name,
            textAlign: TextAlign.center,
            style: bold.copyWith(fontSize: 21),
          ),
          if (store.address.isNotEmpty)
            Text(store.address, textAlign: TextAlign.center, style: body),
          if (store.phone.isNotEmpty)
            Text(
              '${tr('phone')}: ${store.phone}',
              textAlign: TextAlign.center,
              style: body,
            ),
          if (store.gstin.isNotEmpty)
            Text(
              '${tr('gstin')}: ${store.gstin}',
              textAlign: TextAlign.center,
              style: body,
            ),
          divider,
          if (bill.voided)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                bill.voidReason.isEmpty
                    ? tr('voided')
                    : '${tr('voided')}: ${bill.voidReason}',
                textAlign: TextAlign.center,
                style: bold.copyWith(color: KiranaColors.dues, fontSize: 18),
              ),
            ),
          Text('${tr('bill')}: ${bill.number}', style: bold),
          Text(formatDateTime(bill.at, language), style: body),
          if (bill.customerName.isNotEmpty)
            Text('${tr('customer')}: ${bill.customerName}', style: body),
          divider,
          for (final item in bill.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.displayName(language), style: body),
                        Text(
                          '${formatQuantity(item.qtyMilli)} ${unitLabel(tr, item.unit)} × ${formatRupees(item.pricePaise)}',
                          style: body.copyWith(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(formatRupees(item.totalPaise), style: bold),
                ],
              ),
            ),
          divider,
          row(tr('subtotal'), bill.subtotalPaise),
          if (bill.discountPaise > 0) row(tr('discount'), bill.discountPaise),
          row(tr('total'), bill.totalPaise, strong: true),
          divider,
          if (bill.cashPaise > 0) row(tr('cash'), bill.cashPaise),
          if (bill.upiPaise > 0) row(tr('upi'), bill.upiPaise),
          if (bill.creditPaise > 0) row(tr('on_credit'), bill.creditPaise),
          const SizedBox(height: 12),
          Text(
            store.receiptFooter.isNotEmpty
                ? store.receiptFooter
                : tr('thank_you'),
            textAlign: TextAlign.center,
            style: body,
          ),
        ],
      ),
    );
  }
}
