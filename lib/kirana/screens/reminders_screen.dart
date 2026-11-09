import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

enum ReminderChannel { whatsapp, sms }

/// Opens WhatsApp or the SMS app with the message filled in. The shopkeeper
/// presses send there; nothing is sent from this app.
Future<void> sendReminder(
  BuildContext context,
  Customer customer,
  ReminderChannel channel,
) async {
  final session = context.session;
  final tr = context.trNow;
  final store = session.store;
  if (store == null) return;
  final message = reminderMessage(
    language: session.language,
    shopName: store.name,
    customer: customer,
    upiId: store.upiId,
  );
  final uri = channel == ReminderChannel.whatsapp
      ? whatsappUri(customer.phone, message)
      : smsUri(customer.phone, message);
  if (uri == null) {
    showMessage(context, tr('reminder_invalid_phone'));
    return;
  }
  final repo = session.repository;
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Reminder launch failed: $e');
  }
  if (!context.mounted) return;
  if (!opened) {
    showMessage(context, tr('open_app_failed'));
    return;
  }
  repo.logReminder(customer: customer, channel: channel.name);
}

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    return Scaffold(
      appBar: KiranaBar(title: tr('reminders')),
      body: Live<List<Customer>>(
        stream: (repo) => repo.customers(),
        builder: (context, customers) {
          final now = DateTime.now();
          final list = customersToRemind(customers, now);
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.task_alt,
              message: tr('no_reminders'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ReminderCard(
              customer: list[i],
              overdue: list[i].isOverdue(now),
              tr: tr,
              language: language,
            ),
          );
        },
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.customer,
    required this.overdue,
    required this.tr,
    required this.language,
  });

  final Customer customer;
  final bool overdue;
  final Tr tr;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = customer.dueDate;
    final last = customer.lastReminderAt;
    return Card(
      key: ValueKey('remind_${customer.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    customer.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatRupees(customer.balancePaise),
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: KiranaColors.dues,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (overdue) Flag(tr('overdue'), color: KiranaColors.dues),
                if (due != null)
                  Text(tr('due_on', {'date': formatDate(due, language)})),
                Text(
                  last == null
                      ? tr('never_reminded')
                      : tr('last_reminded', {
                          'date': formatDate(last, language),
                        }),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('whatsapp_${customer.id}'),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(tr('whatsapp')),
                    onPressed: () => sendReminder(
                      context,
                      customer,
                      ReminderChannel.whatsapp,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: ValueKey('sms_${customer.id}'),
                    icon: const Icon(Icons.sms_outlined),
                    label: Text(tr('sms')),
                    onPressed: () =>
                        sendReminder(context, customer, ReminderChannel.sms),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
