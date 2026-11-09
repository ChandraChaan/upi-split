import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../utils/dates.dart';
import '../widgets/admin_table.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

class StaffPage extends StatelessWidget {
  const StaffPage({super.key});

  String _storeNames(Tr tr, List<Store> all, Member m) {
    if (m.role.isOwner) return tr('all_stores');
    final names = [for (final s in all) if (m.storeIds.contains(s.id)) s.name];
    return names.isEmpty ? '-' : names.join(', ');
  }

  Future<void> _edit(BuildContext context, Tr tr, SessionController session, Member m) async {
    final values = await showFormDialog(
      context,
      title: tr('edit_staff'),
      specs: [
        ChoiceSpec(
          'role',
          tr('role'),
          {'manager': tr('role_manager'), 'cashier': tr('role_cashier')},
          initial: m.role.name,
        ),
        MultiSpec('stores', tr('store_access'), storeOptions(session.allStores),
            initial: m.storeIds.toSet(), minimum: 1),
        SwitchSpec('active', tr('active'), initial: m.active),
      ],
    );
    if (values == null || !context.mounted) return;
    context.read<SyncMonitor>().track(
          'updateMember',
          () => session.businesses.updateMember(
            session.business!.id,
            m.uid,
            role: MemberRole.values.byName(values.choice('role')!),
            storeIds: values.multi('stores').toList(),
            active: values.flag('active'),
          ),
        );
    showMessage(context, tr('saved'));
  }

  Future<void> _invite(BuildContext context, Tr tr, SessionController session) async {
    final values = await showFormDialog(
      context,
      title: tr('create_invite'),
      description: tr('create_invite_hint'),
      specs: [
        ChoiceSpec(
          'role',
          tr('role'),
          {'manager': tr('role_manager'), 'cashier': tr('role_cashier')},
          initial: 'cashier',
        ),
        MultiSpec('stores', tr('store_access'), storeOptions(session.stores), minimum: 1),
      ],
    );
    if (values == null || !context.mounted) return;
    final sync = context.read<SyncMonitor>();
    final future = session.businesses.createInvite(
      business: session.business!,
      createdBy: session.user!.uid,
      role: MemberRole.values.byName(values.choice('role')!),
      storeIds: values.multi('stores').toList(),
    );
    // The new code also shows up in the open-invites list right away.
    sync.track('createInvite', () => future);
    future.then((invite) {
      if (context.mounted) _showCode(context, invite);
    }, onError: (Object _) {});
  }

  void _showCode(BuildContext context, Invite invite) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tr = dialogContext.tr;
        return AlertDialog(
          title: Text(tr('invite_created')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('invite_created_body', {'date': formatDate(invite.expiresAt)})),
                const SizedBox(height: 16),
                SelectableText(
                  invite.code,
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: invite.code)),
              child: Text(tr('copy_code')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr('close')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _revoke(BuildContext context, Tr tr, SessionController session, Invite invite) async {
    final confirmed = await confirmDialog(
      context,
      title: tr('revoke_invite'),
      message: tr('revoke_invite_body', {'code': invite.code}),
      confirmLabel: tr('revoke'),
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    context.read<SyncMonitor>().track('revokeInvite', () => session.businesses.revokeInvite(invite.code));
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final business = session.business;
    if (business == null) return const SizedBox.shrink();
    final isOwner = session.member?.role.isOwner ?? false;
    final now = DateTime.now();

    final memberColumns = <TableCol<Member>>[
      TableCol.text(tr('name'), (m) => m.name),
      TableCol.text(tr('email'), (m) => m.email),
      TableCol.text(tr('role'), (m) => roleLabel(tr, m.role)),
      TableCol.text(tr('stores'), (m) => _storeNames(tr, session.allStores, m)),
      TableCol(
        tr('status'),
        (m) => m.active
            ? StatusChip(label: tr('active'), color: KiranaColors.received)
            : StatusChip(label: tr('inactive'), color: KiranaColors.dues),
      ),
      if (isOwner)
        TableCol(
          '',
          (m) => m.role.isOwner
              ? const SizedBox.shrink()
              : TextButton(
                  onPressed: () => _edit(context, tr, session, m),
                  child: Text(tr('edit')),
                ),
        ),
    ];

    return PageBody(
      title: tr('staff'),
      actions: [
        FilledButton.icon(
          onPressed: () => _invite(context, tr, session),
          icon: const Icon(Icons.person_add_alt),
          label: Text(tr('create_invite')),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isOwner) ...[Muted(tr('staff_owner_only_note')), const SizedBox(height: kGap)],
          LiveBuilder<List<Member>>(
            cacheKey: 'members-${business.id}',
            create: () => session.businesses.members(business.id),
            builder: (context, members) => AdminTable<Member>(
              columns: memberColumns,
              rows: members,
              emptyMessage: tr('no_staff'),
            ),
          ),
          const SizedBox(height: 24),
          Text(tr('open_invites'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LiveBuilder<List<Invite>>(
            cacheKey: 'invites-${business.id}',
            create: () => session.businesses.openInvites(business.id),
            builder: (context, invites) => AdminTable<Invite>(
              rows: invites,
              emptyMessage: tr('no_open_invites'),
              columns: [
                TableCol<Invite>(
                  tr('invite_code'),
                  (i) => SelectableText(i.code),
                  csv: (i) => i.code,
                ),
                TableCol.text(tr('role'), (i) => roleLabel(tr, i.role)),
                TableCol.text(
                  tr('stores'),
                  (i) => session.allStores
                      .where((s) => i.storeIds.contains(s.id))
                      .map((s) => s.name)
                      .join(', '),
                ),
                TableCol<Invite>(
                  tr('expires'),
                  (i) => i.expiresAt.isBefore(now)
                      ? StatusChip(label: tr('expired'), color: KiranaColors.dues)
                      : Text(formatDate(i.expiresAt)),
                  sortKey: (i) => i.expiresAt,
                ),
                TableCol<Invite>(
                  '',
                  (i) => Wrap(
                    children: [
                      IconButton(
                        tooltip: tr('copy_code'),
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () => Clipboard.setData(ClipboardData(text: i.code)),
                      ),
                      TextButton(
                        onPressed: () => _revoke(context, tr, session, i),
                        child: Text(tr('revoke')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
