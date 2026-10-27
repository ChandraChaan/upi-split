import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:upi_kit/upi_kit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../split/pay_request.dart';
import 'common.dart';

/// What a friend sees when they open a payment link.
class PayPage extends StatelessWidget {
  const PayPage({super.key, required this.request});

  /// Null when the link is broken or incomplete.
  final PayRequest? request;

  @override
  Widget build(BuildContext context) {
    final request = this.request;
    return Scaffold(
      appBar: AppBar(title: const Text('UPI Split')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: request == null
                ? const _BrokenLink()
                : _PayCard(request: request),
          ),
        ),
      ),
    );
  }
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.request});

  final PayRequest request;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final payee = request.payeeName.isEmpty
        ? request.payeeVpa
        : request.payeeName;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    Future<void> open(UpiApp app) async {
      final ok = await launchUrl(
        request.upiLink.toUri(app),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No UPI app opened. Scan the QR code or copy the UPI ID instead.',
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  request.friendName.isEmpty
                      ? 'Your share'
                      : '${request.friendName}, your share',
                  style: text.titleMedium,
                ),
                if (request.note.isNotEmpty)
                  Text(
                    'for ${request.note}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 8),
                Text(
                  formatRupees(request.amountPaise),
                  key: const Key('pay-amount'),
                  style: text.displayMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text('to $payee', style: text.titleMedium),
                Text(
                  request.payeeVpa,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (!isIos)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => open(UpiApp.any),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Pay with a UPI app'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final (app, label) in const [
                        (UpiApp.googlePay, 'Google Pay'),
                        (UpiApp.phonePe, 'PhonePe'),
                        (UpiApp.paytm, 'Paytm'),
                      ])
                        FilledButton(
                          onPressed: () => open(app),
                          child: Text('Pay with $label'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text('Paying from another phone? Scan this.'),
                const SizedBox(height: 12),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(data: request.upiLink.toLink(), size: 200),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          copyText(context, request.payeeVpa, 'UPI ID'),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy UPI ID'),
                    ),
                    TextButton.icon(
                      onPressed: () => copyText(
                        context,
                        UpiAmount.paise(request.amountPaise).format(),
                        'Amount',
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy amount'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'This page only shows the payment details in the link. Nothing '
          'is sent to any server, and the payment happens in your own UPI app.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
          child: const Text('Split your own bill with UPI Split'),
        ),
      ],
    );
  }
}

class _BrokenLink extends StatelessWidget {
  const _BrokenLink();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.link_off, size: 40),
            const SizedBox(height: 12),
            const Text(
              'This payment link is incomplete',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'It may have been cut off when it was copied. Ask the person who '
              'sent it to send it again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/', (_) => false),
              child: const Text('Split a bill with UPI Split'),
            ),
          ],
        ),
      ),
    );
  }
}
