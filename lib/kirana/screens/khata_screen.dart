import 'package:flutter/material.dart';
import 'package:kirana_core/kirana_core.dart';

import '../util/labels.dart';
import '../widgets/common.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

enum _Sort { name, dues }

Color balanceColor(BuildContext context, int paise) {
  if (paise > 0) return KiranaColors.dues;
  if (paise < 0) return KiranaColors.received;
  return Theme.of(context).colorScheme.onSurfaceVariant;
}

class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key});

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  final _query = TextEditingController();
  _Sort _sort = _Sort.name;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.tr;
    final language = context.lang;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: KiranaBar(title: tr('khata')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('khata_add_customer'),
        icon: const Icon(Icons.person_add_alt),
        label: Text(tr('add_customer')),
        onPressed: () => push(context, const CustomerFormScreen()),
      ),
      body: Live<List<Customer>>(
        stream: (repo) => repo.customers(),
        builder: (context, customers) {
          final now = DateTime.now();
          final q = _query.text.trim().toLowerCase();
          final list = customers
              .where(
                (c) => c.name.toLowerCase().contains(q) || c.phone.contains(q),
              )
              .toList();
          if (_sort == _Sort.dues) {
            list.sort((a, b) => b.balancePaise.compareTo(a.balancePaise));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('total_outstanding'),
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Flexible(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: BigNumber(
                              formatRupees(totalOutstanding(customers)),
                              color: KiranaColors.dues,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: TextField(
                  key: const Key('khata_search'),
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: tr('customer_search_hint'),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(tr('sort_name')),
                      selected: _sort == _Sort.name,
                      onSelected: (_) => setState(() => _sort = _Sort.name),
                    ),
                    ChoiceChip(
                      key: const Key('sort_dues'),
                      label: Text(tr('sort_dues')),
                      selected: _sort == _Sort.dues,
                      onSelected: (_) => setState(() => _sort = _Sort.dues),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.menu_book_outlined,
                        message: customers.isEmpty
                            ? tr('no_customers')
                            : tr('no_matches'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = list[i];
                          return ListTile(
                            key: ValueKey('customer_${c.id}'),
                            minTileHeight: 64,
                            title: Text(
                              c.name,
                              style: theme.textTheme.titleMedium,
                            ),
                            subtitle: Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (c.phone.isNotEmpty) Text(c.phone),
                                if (c.lastTxnAt != null)
                                  Text(formatDate(c.lastTxnAt!, language)),
                                if (c.isOverdue(now))
                                  Flag(tr('overdue'), color: KiranaColors.dues),
                              ],
                            ),
                            trailing: _Balance(paise: c.balancePaise, tr: tr),
                            onTap: () => push(
                              context,
                              CustomerDetailScreen(customerId: c.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.paise, required this.tr});

  final int paise;
  final Tr tr;

  @override
  Widget build(BuildContext context) {
    final color = balanceColor(context, paise);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatRupees(paise.abs()),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (paise < 0)
          Text(tr('advance'), style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
