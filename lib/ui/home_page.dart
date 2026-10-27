import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../split/pay_request.dart';
import '../split/split.dart';
import '../split/split_controller.dart';
import 'common.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(splitControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: const Text('UPI Split'),
        actions: [
          TextButton.icon(
            onPressed: controller.newBill,
            icon: const Icon(Icons.add),
            label: const Text('New bill'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          const left = Column(children: [_YouSection(), _BillSection()]);
          const right = Column(children: [_FriendsSection(), _SendSection()]);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: wide
                    ? const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          SizedBox(width: 16),
                          Expanded(child: right),
                        ],
                      )
                    : const Column(children: [left, right]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _YouSection extends ConsumerWidget {
  const _YouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(splitControllerProvider);
    final controller = ref.read(splitControllerProvider.notifier);
    return Section(
      title: 'You paid',
      child: Column(
        children: [
          TextFormField(
            key: const Key('my-name'),
            initialValue: state.myName,
            decoration: const InputDecoration(labelText: 'Your name'),
            textCapitalization: TextCapitalization.words,
            onChanged: controller.setMyName,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('my-vpa'),
            initialValue: state.myVpa,
            decoration: InputDecoration(
              labelText: 'Your UPI ID',
              hintText: 'name@okicici',
              helperText: 'Friends pay this UPI ID. Saved only on this device.',
              errorText: state.myVpa.isNotEmpty && !state.hasValidVpa
                  ? 'Check the UPI ID (name@bank)'
                  : null,
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: controller.setMyVpa,
          ),
        ],
      ),
    );
  }
}

class _BillSection extends ConsumerWidget {
  const _BillSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bill = ref.watch(splitControllerProvider.select((s) => s.bill));
    final controller = ref.read(splitControllerProvider.notifier);
    return Section(
      title: 'The bill',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey('title-${bill.title.isEmpty}'),
            initialValue: bill.title,
            decoration: const InputDecoration(
              labelText: 'What for?',
              hintText: 'Dinner at Meghana\'s',
            ),
            textCapitalization: TextCapitalization.sentences,
            onChanged: controller.setTitle,
          ),
          const SizedBox(height: 12),
          AmountField(
            fieldKey: const Key('total'),
            label: 'Total, including tax and tip',
            paise: bill.totalPaise,
            onChanged: controller.setTotalPaise,
          ),
          const SizedBox(height: 16),
          SegmentedButton<SplitMode>(
            segments: const [
              ButtonSegment(value: SplitMode.equal, label: Text('Equally')),
              ButtonSegment(value: SplitMode.shares, label: Text('By shares')),
              ButtonSegment(value: SplitMode.amounts, label: Text('By amount')),
            ],
            selected: {bill.mode},
            onSelectionChanged: (s) => controller.setMode(s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I had a share too'),
            subtitle: Text(
              bill.mode == SplitMode.amounts
                  ? 'Whatever isn\'t assigned to friends is your share'
                  : bill.includeMe
                  ? 'Split between you and your friends'
                  : 'You paid for your friends only',
            ),
            value: bill.includeMe,
            onChanged: bill.mode == SplitMode.amounts
                ? null
                : controller.setIncludeMe,
          ),
          if (bill.mode == SplitMode.shares && bill.includeMe)
            _SharesStepper(
              label: 'Your shares',
              value: bill.myShares,
              onChanged: controller.setMyShares,
            ),
        ],
      ),
    );
  }
}

class _SharesStepper extends StatelessWidget {
  const _SharesStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Fewer shares for $label',
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: 'More shares for $label',
          onPressed: value < 99 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

class _FriendsSection extends ConsumerStatefulWidget {
  const _FriendsSection();

  @override
  ConsumerState<_FriendsSection> createState() => _FriendsSectionState();
}

class _FriendsSectionState extends ConsumerState<_FriendsSection> {
  final _name = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    ref.read(splitControllerProvider.notifier).addFriend(_name.text);
    _name.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(splitControllerProvider);
    final controller = ref.read(splitControllerProvider.notifier);
    final bill = state.bill;
    final result = state.result;
    final scheme = Theme.of(context).colorScheme;

    return Section(
      title: 'Friends',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('friend-name'),
                  controller: _name,
                  focusNode: _focus,
                  decoration: const InputDecoration(labelText: 'Add a friend'),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _add, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: 8),
          if (bill.friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Add everyone who shared the bill. You don\'t need their '
                'numbers: you\'ll send each one a link.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final friend in bill.friends)
            _FriendRow(
              key: ValueKey(friend.id),
              friend: friend,
              mode: bill.mode,
              owesPaise: result.perFriend[friend.id] ?? 0,
              onChanged: (change) => controller.updateFriend(friend.id, change),
              onRemove: () => controller.removeFriend(friend.id),
            ),
          if (bill.mode == SplitMode.amounts && bill.friends.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                result.unassignedPaise >= 0
                    ? 'Your share: ${formatRupees(result.unassignedPaise)}'
                    : 'Over the total by ${formatRupees(-result.unassignedPaise)}',
                style: TextStyle(
                  color: result.unassignedPaise < 0
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    super.key,
    required this.friend,
    required this.mode,
    required this.owesPaise,
    required this.onChanged,
    required this.onRemove,
  });

  final Friend friend;
  final SplitMode mode;
  final int owesPaise;
  final ValueChanged<Friend Function(Friend)> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              friend.name,
              style: Theme.of(context).textTheme.bodyLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          switch (mode) {
            SplitMode.equal => const SizedBox.shrink(),
            SplitMode.shares => _SharesStepper(
              label: friend.name,
              value: friend.shares,
              onChanged: (v) => onChanged((f) => f.copyWith(shares: v)),
            ),
            SplitMode.amounts => SizedBox(
              width: 130,
              child: AmountField(
                fieldKey: Key('amount-${friend.id}'),
                paise: friend.customPaise,
                onChanged: (v) => onChanged((f) => f.copyWith(customPaise: v)),
              ),
            ),
          },
          if (mode != SplitMode.amounts)
            SizedBox(
              width: 96,
              child: Text(
                formatRupees(owesPaise),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          IconButton(
            tooltip: 'Remove ${friend.name}',
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SendSection extends ConsumerWidget {
  const _SendSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(splitControllerProvider);
    final controller = ref.read(splitControllerProvider.notifier);
    final result = state.result;
    final requests = state.requests;
    final scheme = Theme.of(context).colorScheme;

    final blocker = !state.hasValidVpa
        ? 'Add your UPI ID to send requests.'
        : state.bill.totalPaise == 0
        ? 'Enter the bill total.'
        : state.bill.friends.isEmpty
        ? 'Add the friends who shared it.'
        : result.unassignedPaise < 0
        ? 'The amounts add up to more than the bill.'
        : requests.isEmpty
        ? 'Nobody owes anything yet.'
        : null;

    final paidCount = requests.where((r) => r.$1.paid).length;

    return Section(
      title: 'Send requests',
      child: blocker != null
          ? Text(blocker, style: TextStyle(color: scheme.onSurfaceVariant))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'You get back ${formatRupees(result.owedToMePaise)} '
                  'from ${requests.length} '
                  '${requests.length == 1 ? 'friend' : 'friends'}'
                  '${result.myPaise > 0 ? ' · your share ${formatRupees(result.myPaise)}' : ''}',
                  key: const Key('summary'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (paidCount > 0)
                  Text(
                    '$paidCount of ${requests.length} paid',
                    style: TextStyle(color: scheme.primary),
                  ),
                const SizedBox(height: 8),
                for (final (friend, request) in requests)
                  _RequestTile(
                    friend: friend,
                    request: request,
                    onPaid: (paid) => controller.updateFriend(
                      friend.id,
                      (f) => f.copyWith(paid: paid),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () =>
                      _openWhatsApp(_groupMessage(state.bill.title, requests)),
                  icon: const Icon(Icons.groups_outlined),
                  label: const Text('Send everyone\'s links to a group'),
                ),
              ],
            ),
    );
  }
}

String _groupMessage(String title, List<(Friend, PayRequest)> requests) {
  final lines = [
    if (title.trim().isNotEmpty) '${title.trim()}: who owes what',
    for (final (friend, request) in requests)
      '${friend.name}: ${formatRupees(request.amountPaise)} → ${request.shareUrl()}',
    'Tap your link to pay with any UPI app.',
  ];
  return lines.join('\n');
}

Future<void> _openWhatsApp(String message) => launchUrl(
  Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),
  mode: LaunchMode.externalApplication,
);

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.friend,
    required this.request,
    required this.onPaid,
  });

  final Friend friend;
  final PayRequest request;
  final ValueChanged<bool> onPaid;

  @override
  Widget build(BuildContext context) {
    final done = friend.paid;
    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        child: Row(
          children: [
            Checkbox(
              value: done,
              onChanged: (v) => onPaid(v ?? false),
              semanticLabel: '${friend.name} has paid',
            ),
            Expanded(
              child: Text(
                '${friend.name} · ${formatRupees(request.amountPaise)}',
                style: TextStyle(
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Send ${friend.name} a WhatsApp message',
              onPressed: () => _openWhatsApp(messageFor(request)),
              icon: const Icon(Icons.chat_outlined),
            ),
            IconButton(
              tooltip: 'Copy ${friend.name}\'s message',
              onPressed: () =>
                  copyText(context, messageFor(request), 'Message'),
              icon: const Icon(Icons.copy),
            ),
            IconButton(
              tooltip: 'Show a QR code for ${friend.name} to scan',
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _QrDialog(request: request),
              ),
              icon: const Icon(Icons.qr_code_2),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrDialog extends StatelessWidget {
  const _QrDialog({required this.request});

  final PayRequest request;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '${request.friendName} pays ${formatRupees(request.amountPaise)}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: request.upiLink.toLink(), size: 220),
          ),
          const SizedBox(height: 12),
          const Text('Scan with any UPI app to pay'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
