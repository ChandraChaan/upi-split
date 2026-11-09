import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';
import 'package:provider/provider.dart';

import '../util/labels.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    final tr = context.trNow;
    final session = context.session;
    final ok = await confirm(
      context,
      title: tr('sign_out'),
      body: tr('sign_out_body'),
      action: tr('sign_out'),
    );
    if (ok) await session.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final session = context.watch<SessionController>();
    final store = session.store;
    final stores = session.stores;
    final member = session.member;
    final isOwner = member?.role.isOwner ?? false;
    return Scaffold(
      appBar: KiranaBar(title: tr('settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(tr('language')),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: LanguageToggle(),
          ),
          if (stores.length > 1) ...[
            SectionTitle(tr('switch_store')),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final s in stores)
                    ListTile(
                      key: ValueKey('store_${s.id}'),
                      minTileHeight: 56,
                      title: Text(s.name),
                      trailing: s.id == store?.id
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: () => session.selectStore(s.id),
                    ),
                ],
              ),
            ),
          ],
          if (isOwner && store != null) ...[
            SectionTitle(tr('store_details')),
            Card(
              child: ListTile(
                key: const Key('edit_store'),
                minTileHeight: 60,
                leading: const Icon(Icons.storefront_outlined),
                title: Text(store.name),
                subtitle: store.address.isEmpty ? null : Text(store.address),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => push(context, StoreDetailsScreen(store: store)),
              ),
            ),
          ],
          SectionTitle(tr('account')),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  if (member != null) LabelValue(tr('name'), member.name),
                  LabelValue(
                    tr('email'),
                    session.user?.email ?? member?.email ?? '',
                  ),
                  if (member != null)
                    LabelValue(tr('role'), roleLabel(tr, member.role)),
                  if (session.business != null)
                    LabelValue(tr('business'), session.business!.name),
                  if (store != null) LabelValue(tr('store'), store.name),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('sign_out'),
            icon: const Icon(Icons.logout),
            label: Text(tr('sign_out')),
            onPressed: () => _signOut(context),
          ),
        ],
      ),
    );
  }
}

class StoreDetailsScreen extends StatefulWidget {
  const StoreDetailsScreen({super.key, required this.store});

  final Store store;

  @override
  State<StoreDetailsScreen> createState() => _StoreDetailsScreenState();
}

class _StoreDetailsScreenState extends State<StoreDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final _address = TextEditingController(text: widget.store.address);
  late final _phone = TextEditingController(text: widget.store.phone);
  late final _gstin = TextEditingController(text: widget.store.gstin);
  late final _upi = TextEditingController(text: widget.store.upiId);
  late final _footer = TextEditingController(text: widget.store.receiptFooter);

  @override
  void dispose() {
    _address.dispose();
    _phone.dispose();
    _gstin.dispose();
    _upi.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final tr = context.trNow;
    final session = context.session;
    final sync = context.read<SyncMonitor>();
    final businessId = session.business!.id;
    final updated = Store(
      id: widget.store.id,
      name: widget.store.name,
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      gstin: _gstin.text.trim().toUpperCase(),
      upiId: _upi.text.trim(),
      receiptFooter: _footer.text.trim(),
    );
    // Queues offline like every other write; a rejection reaches the root.
    sync.track(
      'updateStore',
      () => session.businesses.updateStore(businessId, updated),
    );
    showMessage(context, tr('saved'));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: KiranaBar(title: tr('store_details')),
      body: Form(
        key: _form,
        child: ScrollColumn(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.store.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            gap,
            TextFormField(
              key: const Key('store_address'),
              controller: _address,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('address')),
            ),
            gap,
            TextFormField(
              key: const Key('store_phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('phone')),
              validator: V.phone(tr),
            ),
            gap,
            TextFormField(
              key: const Key('store_gstin'),
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('gstin')),
              validator: V.gstin(tr),
            ),
            gap,
            TextFormField(
              key: const Key('store_upi'),
              controller: _upi,
              decoration: InputDecoration(
                labelText: tr('upi_id'),
                hintText: tr('upi_hint'),
              ),
              validator: (v) {
                final text = v?.trim() ?? '';
                if (text.isEmpty) return null;
                return RegExp(r'^[\w.\-]{2,}@[A-Za-z]{2,}$').hasMatch(text)
                    ? null
                    : tr('invalid_upi');
              },
            ),
            gap,
            TextFormField(
              key: const Key('store_footer'),
              controller: _footer,
              maxLines: 2,
              decoration: InputDecoration(labelText: tr('receipt_footer')),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomAction(
        child: FilledButton(
          key: const Key('store_save'),
          onPressed: _save,
          child: Text(tr('save')),
        ),
      ),
    );
  }
}
